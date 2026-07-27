import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-backup-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const TABLES = [
  "profiles",
  "projects",
  "activities",
  "work_areas",
  "manufacturing_sectors",
  "modules",
  "rooms",
  "panel_types",
  "activity_area_links",
  "project_modules",
  "project_rooms",
  "project_room_modules",
  "time_entries",
  "absences",
  "monthly_closings",
  "holidays",
] as const;

type TableName = typeof TABLES[number];

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function countBackupRecords(tables: Record<string, unknown[]>): number {
  return Object.values(tables).reduce(
    (sum, rows) => sum + (Array.isArray(rows) ? rows.length : 0),
    0,
  );
}

async function getAuthenticatedAdmin(
  admin: ReturnType<typeof createClient>,
  request: Request,
) {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return {error: "Usuário não autenticado.", status: 401};
  }

  const jwt = authorization.slice("Bearer ".length);
  const {
    data: {user},
    error: userError,
  } = await admin.auth.getUser(jwt);

  if (userError || !user) {
    return {error: "Sessão inválida ou expirada.", status: 401};
  }

  const {data: profile, error: profileError} = await admin
    .from("profiles")
    .select("id, full_name, email, role, active")
    .eq("id", user.id)
    .single();

  if (
    profileError ||
    !profile ||
    !profile.active ||
    profile.role !== "administrador"
  ) {
    return {
      error: "Somente administradores podem gerar ou restaurar backups.",
      status: 403,
    };
  }

  return {profile, user};
}

async function exportTables(admin: ReturnType<typeof createClient>) {
  const tables: Record<string, unknown[]> = {};
  const pageSize = 1000;

  for (const table of TABLES) {
    const rows: unknown[] = [];
    for (let from = 0; ; from += pageSize) {
      const {data, error} = await admin
        .from(table)
        .select("*")
        .range(from, from + pageSize - 1);
      if (error) {
        throw new Error(`Falha ao exportar ${table}: ${error.message}`);
      }
      rows.push(...(data || []));
      if (!data || data.length < pageSize) break;
    }
    tables[table] = rows;
  }

  return tables;
}

async function getValidAuthUserIds(
  admin: ReturnType<typeof createClient>,
  profileRows: Record<string, unknown>[],
): Promise<Set<string>> {
  const valid = new Set<string>();

  for (const row of profileRows) {
    const id = String(row?.id || "");
    if (!id) continue;

    const {data, error} = await admin.auth.admin.getUserById(id);
    if (!error && data?.user) valid.add(id);
  }

  return valid;
}

async function upsertRows(
  admin: ReturnType<typeof createClient>,
  table: TableName,
  rows: Record<string, unknown>[],
) {
  if (!rows.length) return 0;

  const chunkSize = 200;
  let processed = 0;

  for (let index = 0; index < rows.length; index += chunkSize) {
    const chunk = rows.slice(index, index + chunkSize);
    const conflictKeys: Partial<Record<TableName, string>> = {
      work_areas: "code",
      activity_area_links: "activity_id,area_code",
      project_modules: "project_id,module_id",
      project_rooms: "project_id,room_id",
      project_room_modules: "project_id,room_id,module_id",
    };
    const {error} = await admin
      .from(table)
      .upsert(chunk, {onConflict: conflictKeys[table] || "id"});

    if (error) {
      throw new Error(`Falha ao restaurar ${table}: ${error.message}`);
    }

    processed += chunk.length;
  }

  return processed;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {headers: corsHeaders});
  }

  if (request.method !== "POST") {
    return jsonResponse({error: "Método não permitido."}, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const configuredBackupToken = Deno.env.get("BACKUP_TOKEN");

    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(
        {error: "Configuração interna do Supabase ausente."},
        500,
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {persistSession: false, autoRefreshToken: false},
    });

    const body = await request.json().catch(() => null);
    const action = String(body?.action || "").toLowerCase();
    const suppliedBackupToken = request.headers.get("x-backup-token") || "";

    const isAutomaticAgent =
      action === "export" &&
      Boolean(configuredBackupToken) &&
      suppliedBackupToken.length >= 32 &&
      suppliedBackupToken === configuredBackupToken;

    let actor = "Agente automático do Windows";

    if (!isAutomaticAgent) {
      const authResult = await getAuthenticatedAdmin(admin, request);
      if ("error" in authResult) {
        return jsonResponse({error: authResult.error}, authResult.status);
      }
      actor = authResult.profile.email || authResult.profile.full_name;
    }

    if (action === "export") {
      const tables = await exportTables(admin);
      const recordCount = countBackupRecords(tables);
      const exportedAt = new Date().toISOString();

      return jsonResponse({
        ok: true,
        recordCount,
        backup: {
          format: "aponta-p3-backup",
          version: "2.12.0",
          exportedAt,
          exportedBy: actor,
          sourceProjectUrl: supabaseUrl,
          tables,
        },
      });
    }

    if (action !== "restore") {
      return jsonResponse({error: "Ação inválida."}, 400);
    }

    if (isAutomaticAgent) {
      return jsonResponse(
        {error: "O agente automático não possui permissão de restauração."},
        403,
      );
    }

    const backup = body?.backup;
    if (
      !backup ||
      backup.format !== "aponta-p3-backup" ||
      typeof backup.tables !== "object"
    ) {
      return jsonResponse({error: "Arquivo de backup inválido."}, 400);
    }

    const backupTables = backup.tables as Record<
      string,
      Record<string, unknown>[]
    >;

    const profileRows = Array.isArray(backupTables.profiles)
      ? backupTables.profiles
      : [];

    const validUserIds = await getValidAuthUserIds(admin, profileRows);
    let restoredRecords = 0;
    let skippedRecords = profileRows.length - validUserIds.size;

    const validProfiles = profileRows.filter((row) =>
      validUserIds.has(String(row.id || ""))
    );
    restoredRecords += await upsertRows(admin, "profiles", validProfiles);

    const projectRows = (backupTables.projects || []).map((row) => ({
      ...row,
      created_by: validUserIds.has(String(row.created_by || ""))
        ? row.created_by
        : null,
    }));
    restoredRecords += await upsertRows(admin, "projects", projectRows);

    const activityRows = (backupTables.activities || []).map((row) => ({
      ...row,
      created_by: validUserIds.has(String(row.created_by || ""))
        ? row.created_by
        : null,
    }));
    restoredRecords += await upsertRows(admin, "activities", activityRows);

    restoredRecords += await upsertRows(admin, "work_areas", backupTables.work_areas || []);
    restoredRecords += await upsertRows(admin, "manufacturing_sectors", backupTables.manufacturing_sectors || []);
    restoredRecords += await upsertRows(admin, "modules", backupTables.modules || []);
    restoredRecords += await upsertRows(admin, "rooms", backupTables.rooms || []);
    restoredRecords += await upsertRows(admin, "panel_types", backupTables.panel_types || []);
    restoredRecords += await upsertRows(admin, "activity_area_links", backupTables.activity_area_links || []);
    restoredRecords += await upsertRows(admin, "project_modules", backupTables.project_modules || []);
    restoredRecords += await upsertRows(admin, "project_rooms", backupTables.project_rooms || []);
    restoredRecords += await upsertRows(admin, "project_room_modules", backupTables.project_room_modules || []);

    restoredRecords += await upsertRows(
      admin,
      "holidays",
      backupTables.holidays || [],
    );

    const entryRows = (backupTables.time_entries || []).filter((row) =>
      validUserIds.has(String(row.user_id || ""))
    );
    skippedRecords +=
      (backupTables.time_entries || []).length - entryRows.length;
    restoredRecords += await upsertRows(admin, "time_entries", entryRows);

    const absenceRows = (backupTables.absences || []).filter((row) =>
      validUserIds.has(String(row.user_id || ""))
    );
    skippedRecords +=
      (backupTables.absences || []).length - absenceRows.length;
    restoredRecords += await upsertRows(admin, "absences", absenceRows);

    const closingRows = (backupTables.monthly_closings || [])
      .filter((row) => validUserIds.has(String(row.user_id || "")))
      .map((row) => ({
        ...row,
        reviewed_by: validUserIds.has(String(row.reviewed_by || ""))
          ? row.reviewed_by
          : null,
      }));
    skippedRecords +=
      (backupTables.monthly_closings || []).length - closingRows.length;
    restoredRecords += await upsertRows(
      admin,
      "monthly_closings",
      closingRows,
    );

    return jsonResponse({
      ok: true,
      restoredRecords,
      skippedRecords,
      mode: "merge",
    });
  } catch (error) {
    console.error(error);
    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : "Erro inesperado na função de backup.",
      },
      500,
    );
  }
});
