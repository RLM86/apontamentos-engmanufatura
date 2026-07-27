import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método não permitido." }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) return json({ error: "Configuração interna ausente." }, 500);

    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Usuário não autenticado." }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const token = authorization.slice("Bearer ".length);
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Sessão inválida ou expirada." }, 401);

    const callerId = authData.user.id;
    const { data: caller } = await admin
      .from("profiles")
      .select("id, role, active")
      .eq("id", callerId)
      .single();

    if (!caller?.active || caller.role !== "administrador") {
      return json({ error: "Somente Administradores podem excluir colaboradores." }, 403);
    }

    const payload = await request.json().catch(() => null);
    const userId = String(payload?.userId || "");
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return json({ error: "Colaborador inválido." }, 400);
    if (userId === callerId) return json({ error: "Você não pode excluir o próprio usuário administrador." }, 422);

    const { data: profile } = await admin
      .from("profiles")
      .select("id, full_name, email")
      .eq("id", userId)
      .single();
    if (!profile) return json({ error: "Colaborador não encontrado." }, 404);

    const checks = [
      { table: "time_entries", column: "user_id", label: "apontamentos" },
      { table: "absences", column: "user_id", label: "férias/afastamentos" },
      { table: "monthly_closings", column: "user_id", label: "fechamentos" },
      { table: "monthly_closings", column: "reviewed_by", label: "aprovações realizadas" },
    ];

    const dependencies: Record<string, number> = {};
    for (const check of checks) {
      const { count, error } = await admin
        .from(check.table)
        .select("id", { count: "exact", head: true })
        .eq(check.column, userId);
      if (error) return json({ error: `Não foi possível conferir ${check.label}.` }, 500);
      dependencies[check.label] = count || 0;
    }

    if (Object.values(dependencies).some((count) => count > 0)) {
      return json({
        error: "O colaborador possui histórico. Desative-o em vez de excluir.",
        dependencies,
      }, 409);
    }

    await admin.from("projects").update({ created_by: null }).eq("created_by", userId);
    await admin.from("activities").update({ created_by: null }).eq("created_by", userId);

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) return json({ error: `Falha ao excluir acesso: ${deleteError.message}` }, 500);

    return json({ ok: true, deletedUserId: userId, deletedName: profile.full_name });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Erro inesperado." }, 500);
  }
});
