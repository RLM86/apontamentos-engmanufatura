import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function errorResponse(
  code: string,
  message: string,
  status: number,
  details: unknown = null,
): Response {
  return response(
    {
      sent: false,
      error: message,
      code,
      details,
    },
    status,
  );
}

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (character) => {
    const entities: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    };
    return entities[character];
  });
}

function formatHours(value: number): string {
  return value.toLocaleString("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return errorResponse("METHOD_NOT_ALLOWED", "Método não permitido.", 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const emailFrom =
      Deno.env.get("EMAIL_FROM") || "Aponta P3 <onboarding@resend.dev>";
    const fixedRecipients = Deno.env.get("APPROVAL_EMAILS") || "";

    if (!supabaseUrl || !serviceRoleKey) {
      return errorResponse("SUPABASE_CONFIG_MISSING", "Configuração interna do Supabase ausente.", 500);
    }

    if (!resendApiKey) {
      return errorResponse("RESEND_API_KEY_MISSING", "O segredo RESEND_API_KEY não foi configurado em Edge Functions → Secrets.", 500);
    }

    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return errorResponse("USER_NOT_AUTHENTICATED", "Usuário não autenticado.", 401);
    }

    const jwt = authorization.replace("Bearer ", "");
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const {
      data: { user },
      error: userError,
    } = await admin.auth.getUser(jwt);

    if (userError || !user) {
      return errorResponse("INVALID_SESSION", "Sessão inválida ou expirada. Saia e entre novamente no aplicativo.", 401);
    }

    const body = await request.json().catch(() => null);
    const userId = String(body?.userId || "");
    const month = String(body?.month || "");

    if (!/^[0-9a-f-]{36}$/i.test(userId)) {
      return errorResponse("INVALID_EMPLOYEE", "Colaborador inválido.", 400);
    }

    if (!/^\d{4}-\d{2}-01$/.test(month)) {
      return errorResponse("INVALID_MONTH", "Mês de referência inválido.", 400);
    }

    const { data: caller, error: callerError } = await admin
      .from("profiles")
      .select("id, full_name, email, role, active")
      .eq("id", user.id)
      .single();

    if (callerError || !caller?.active) {
      return errorResponse("INVALID_CALLER_PROFILE", "Perfil do usuário inválido ou inativo.", 403);
    }

    const canSubmitForOthers =
      caller.role === "administrador" || caller.role === "gestor";

    if (userId !== user.id && !canSubmitForOthers) {
      return errorResponse(
        "FORBIDDEN_OTHER_EMPLOYEE",
        "Você não tem permissão para enviar o fechamento de outro colaborador.",
        403,
      );
    }

    const { data: employee, error: employeeError } = await admin
      .from("profiles")
      .select("id, full_name, email, active")
      .eq("id", userId)
      .single();

    if (employeeError || !employee?.active) {
      return errorResponse("EMPLOYEE_NOT_FOUND", "Colaborador não encontrado ou inativo.", 404);
    }

    const [year, monthNumber] = month.slice(0, 7).split("-").map(Number);
    const nextMonth = new Date(Date.UTC(year, monthNumber, 1))
      .toISOString()
      .slice(0, 10);

    const { data: entries, error: entriesError } = await admin
      .from("time_entries")
      .select("hours")
      .eq("user_id", userId)
      .gte("entry_date", month)
      .lt("entry_date", nextMonth);

    if (entriesError) {
      return errorResponse("ENTRIES_QUERY_FAILED", "Não foi possível calcular as horas do período.", 500);
    }

    const totalHours = (entries || []).reduce(
      (sum, entry) => sum + Number(entry.hours || 0),
      0,
    );

    let recipients = fixedRecipients
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean);

    if (recipients.length === 0) {
      const { data: approvers, error: approversError } = await admin
        .from("profiles")
        .select("email")
        .eq("active", true)
        .in("role", ["administrador", "gestor"]);

      if (approversError) {
        return errorResponse("APPROVERS_QUERY_FAILED", "Não foi possível localizar os aprovadores.", 500);
      }

      recipients = (approvers || [])
        .map((profile) => String(profile.email || "").trim().toLowerCase())
        .filter(Boolean);
    }

    recipients = [...new Set(recipients)];

    if (recipients.length === 0) {
      return errorResponse(
        "NO_APPROVAL_RECIPIENTS",
        "Nenhum Administrador ou Gestor ativo possui e-mail cadastrado. Cadastre um e-mail ou configure APPROVAL_EMAILS.",
        422,
      );
    }

    const monthLabel = new Date(`${month}T12:00:00Z`).toLocaleDateString("pt-BR", {
      month: "long",
      year: "numeric",
      timeZone: "UTC",
    });

    const applicationUrl =
      Deno.env.get("APP_URL") ||
      request.headers.get("origin") ||
      "";

    const employeeName = escapeHtml(employee.full_name);
    const senderName = escapeHtml(caller.full_name);
    const safeMonth = escapeHtml(monthLabel);
    const safeUrl = escapeHtml(applicationUrl);
    const safeHours = formatHours(totalHours);

    const actionButton = applicationUrl
      ? `<p style="margin:24px 0">
           <a href="${safeUrl}" style="display:inline-block;background:#174a73;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:700">
             Abrir Aponta P3
           </a>
         </p>`
      : "";

    const html = `
      <div style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#1f2937">
        <div style="background:#174a73;color:#ffffff;padding:20px;border-radius:12px 12px 0 0">
          <h1 style="margin:0;font-size:22px">Fechamento aguardando aprovação</h1>
        </div>
        <div style="border:1px solid #d8e1eb;border-top:0;padding:22px;border-radius:0 0 12px 12px">
          <p>Um fechamento mensal foi enviado para aprovação.</p>
          <table style="width:100%;border-collapse:collapse">
            <tr>
              <td style="padding:8px;border-bottom:1px solid #e5e7eb"><strong>Colaborador</strong></td>
              <td style="padding:8px;border-bottom:1px solid #e5e7eb">${employeeName}</td>
            </tr>
            <tr>
              <td style="padding:8px;border-bottom:1px solid #e5e7eb"><strong>Período</strong></td>
              <td style="padding:8px;border-bottom:1px solid #e5e7eb">${safeMonth}</td>
            </tr>
            <tr>
              <td style="padding:8px;border-bottom:1px solid #e5e7eb"><strong>Total de horas</strong></td>
              <td style="padding:8px;border-bottom:1px solid #e5e7eb">${safeHours} h</td>
            </tr>
            <tr>
              <td style="padding:8px"><strong>Enviado por</strong></td>
              <td style="padding:8px">${senderName}</td>
            </tr>
          </table>
          ${actionButton}
          <p style="font-size:13px;color:#667085">
            Mensagem automática do sistema Aponta P3.
          </p>
        </div>
      </div>
    `;

    const text = [
      "Fechamento aguardando aprovação",
      `Colaborador: ${employee.full_name}`,
      `Período: ${monthLabel}`,
      `Total de horas: ${safeHours} h`,
      `Enviado por: ${caller.full_name}`,
      applicationUrl ? `Abrir aplicativo: ${applicationUrl}` : "",
    ]
      .filter(Boolean)
      .join("\n");

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: emailFrom,
        to: recipients,
        subject: `Aprovação de horas — ${employee.full_name} — ${monthLabel}`,
        html,
        text,
      }),
    });

    const resendData = await resendResponse.json().catch(() => ({}));

    if (!resendResponse.ok) {
      console.error("Erro Resend:", {
        status: resendResponse.status,
        name: resendData?.name || null,
        message: resendData?.message || null,
      });

      const resendMessage = String(
        resendData?.message || "O provedor de e-mail recusou a mensagem."
      );

      let code = "RESEND_REJECTED";
      let userMessage = resendMessage;

      if (resendResponse.status === 429) {
        code = "RESEND_RATE_LIMIT";
        userMessage =
          "O limite de envio do Resend foi atingido. Aguarde a liberação do limite ou verifique o plano da conta.";
      } else if (
        /domain|verify|verified|resend\.dev|testing/i.test(resendMessage)
      ) {
        code = "RESEND_DOMAIN_NOT_VERIFIED";
        userMessage =
          "O remetente não está autorizado. Verifique um domínio no Resend e configure EMAIL_FROM com esse domínio. O onboarding@resend.dev envia somente para o e-mail da própria conta Resend.";
      } else if (/api.?key|unauthorized|authentication/i.test(resendMessage)) {
        code = "RESEND_INVALID_API_KEY";
        userMessage =
          "A chave RESEND_API_KEY é inválida, foi revogada ou não possui permissão de envio.";
      } else if (/recipient|to address|invalid.*email/i.test(resendMessage)) {
        code = "RESEND_INVALID_RECIPIENT";
        userMessage =
          "Um dos e-mails dos aprovadores é inválido. Confira os e-mails dos Gestores/Administradores ou o segredo APPROVAL_EMAILS.";
      }

      return errorResponse(
        code,
        userMessage,
        resendResponse.status >= 400 && resendResponse.status < 600
          ? resendResponse.status
          : 502,
        {
          provider: "resend",
          provider_status: resendResponse.status,
          provider_message: resendMessage,
        },
      );
    }

    return response({
      sent: true,
      recipients: recipients.length,
      emailId: resendData?.id || null,
    });
  } catch (error) {
    console.error(error);
    return errorResponse(
      "UNEXPECTED_ERROR",
      error instanceof Error ? error.message : "Erro inesperado.",
      500,
    );
  }
});
