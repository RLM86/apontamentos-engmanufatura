/*
 * APONTA HORAS — CORREÇÃO DE RECUPERAÇÃO DE SENHA
 * Versão: 2026.08.03
 *
 * Requisitos:
 * 1. O cliente Supabase do app deve ser exposto:
 *    window.apontaSupabase = supabase;
 * 2. Este arquivo deve ser carregado depois de app.js.
 */

(function () {
  "use strict";

  const RECOVERY_PAGE = "/redefinir-senha.html";

  function getClient() {
    const candidates = [
      window.apontaSupabase,
      window.supabaseClient,
      window.sbClient,
      window.appSupabase,
    ];

    const client = candidates.find(
      (item) =>
        item &&
        item.auth &&
        typeof item.auth.resetPasswordForEmail === "function"
    );

    if (!client) {
      throw new Error(
        "Cliente Supabase não encontrado. Adicione window.apontaSupabase = supabase após criar o cliente."
      );
    }

    return client;
  }

  function normalizeEmail(value) {
    return String(value || "").trim().toLowerCase();
  }

  function isValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  async function sendPasswordRecovery(email) {
    const normalizedEmail = normalizeEmail(email);

    if (!isValidEmail(normalizedEmail)) {
      throw new Error("Informe um e-mail válido.");
    }

    const client = getClient();
    const redirectTo = `${window.location.origin}${RECOVERY_PAGE}`;

    const { error } = await client.auth.resetPasswordForEmail(
      normalizedEmail,
      { redirectTo }
    );

    if (error) {
      throw error;
    }

    return {
      ok: true,
      redirectTo,
      message:
        "E-mail de redefinição enviado. Verifique também a caixa de spam.",
    };
  }

  window.ApontaPasswordRecovery = {
    send: sendPasswordRecovery,
    recoveryPage: RECOVERY_PAGE,
  };
})();
