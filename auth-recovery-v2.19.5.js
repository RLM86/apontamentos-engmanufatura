(() => {
  "use strict";

  const PRIMARY_APP_URL =
    "https://apontamentos-engmanufatura.modulardtc.workers.dev/";

  const cfg = window.APONTA_CONFIG || {};
  const $ = id => document.getElementById(id);

  const form = $("otpRecoveryForm");
  const message = $("recoveryMessage");
  const button = $("saveNewPasswordBtn");
  const validation = $("recoveryValidation");
  const loading = $("loading");

  function setLoading(active, text = "Validando código...") {
    if (!loading) return;
    const label = loading.querySelector("span");
    if (label) label.textContent = text;
    loading.hidden = !active;
  }

  function showMessage(text, error = false) {
    message.textContent = text;
    message.classList.toggle("error", error);
    message.hidden = false;
  }

  function clearMessage() {
    message.textContent = "";
    message.hidden = true;
    message.classList.remove("error");
  }

  function normalizeError(error) {
    return String(
      error?.message ||
      error?.error_description ||
      error?.code ||
      error ||
      ""
    ).toLowerCase();
  }

  function recoveryErrorMessage(error) {
    const normalized = normalizeError(error);

    if (
      normalized.includes("expired") ||
      normalized.includes("invalid") ||
      normalized.includes("otp") ||
      normalized.includes("token")
    ) {
      return (
        "Código inválido ou expirado. Solicite um novo código e use somente " +
        "o código do e-mail mais recente."
      );
    }

    if (
      normalized.includes("rate") ||
      normalized.includes("too many") ||
      normalized.includes("429")
    ) {
      return (
        "Muitas tentativas foram realizadas. Aguarde alguns minutos antes " +
        "de tentar novamente."
      );
    }

    if (
      normalized.includes("fetch") ||
      normalized.includes("network") ||
      normalized.includes("connection")
    ) {
      return (
        "Não foi possível conectar ao serviço de autenticação. Verifique a " +
        "internet e tente novamente."
      );
    }

    return error?.message || "Não foi possível alterar a senha.";
  }

  const configured =
    /^https:\/\/.+\.supabase\.co$/.test(cfg.supabaseUrl || "") &&
    typeof cfg.supabaseAnonKey === "string" &&
    cfg.supabaseAnonKey.length > 30 &&
    !cfg.supabaseAnonKey.includes("COLE_");

  if (!configured) {
    form.hidden = true;
    showMessage("A configuração do Supabase não foi carregada.", true);
    return;
  }

  const sb = window.supabase.createClient(
    cfg.supabaseUrl,
    cfg.supabaseAnonKey,
    {
      auth: {
        detectSessionInUrl: false,
        persistSession: false,
        autoRefreshToken: false,
        flowType: "pkce"
      }
    }
  );

  const currentUrl = new URL(window.location.href);
  const savedEmail =
    sessionStorage.getItem("aponta_recovery_email") ||
    currentUrl.searchParams.get("email") ||
    "";

  $("recoveryEmail").value = savedEmail;

  $("recoveryCode").addEventListener("input", event => {
    event.target.value = event.target.value
      .replace(/\D/g, "")
      .slice(0, 6);
  });

  if (savedEmail) {
    $("recoveryCode").focus();
  } else {
    $("recoveryEmail").focus();
  }

  form.addEventListener("submit", async event => {
    event.preventDefault();
    clearMessage();

    const email = $("recoveryEmail").value.trim().toLowerCase();
    const token = $("recoveryCode").value.trim();
    const password = $("newPassword").value;
    const confirmation = $("confirmNewPassword").value;

    if (!$("recoveryEmail").checkValidity()) {
      showMessage("Informe um endereço de e-mail válido.", true);
      $("recoveryEmail").focus();
      return;
    }

    if (!/^\d{6}$/.test(token)) {
      showMessage(
        "Informe exatamente os 6 dígitos recebidos por e-mail.",
        true
      );
      $("recoveryCode").focus();
      return;
    }

    if (password.length < 6) {
      showMessage("A senha deve possuir pelo menos 6 caracteres.", true);
      $("newPassword").focus();
      return;
    }

    if (password !== confirmation) {
      showMessage("As senhas informadas não são iguais.", true);
      $("confirmNewPassword").focus();
      return;
    }

    const originalText = button.textContent;
    button.disabled = true;
    button.textContent = "Validando código...";
    setLoading(true, "Validando código...");

    try {
      const { data: verification, error: verifyError } =
        await sb.auth.verifyOtp({
          email,
          token,
          type: "recovery"
        });

      if (verifyError) throw verifyError;

      if (!verification?.session) {
        throw new Error(
          "O código foi reconhecido, mas a sessão de recuperação não foi criada."
        );
      }

      button.textContent = "Alterando senha...";
      setLoading(true, "Alterando senha...");

      const { error: updateError } = await sb.auth.updateUser({
        password
      });

      if (updateError) throw updateError;

      sessionStorage.removeItem("aponta_recovery_email");

      validation.innerHTML =
        '<div class="recovery-success">' +
        "<h2>Senha alterada com sucesso</h2>" +
        "<p>Você já pode entrar no Aponta Horas usando a nova senha.</p>" +
        "</div>";

      form.reset();
      form.hidden = true;

      showMessage(
        "A nova senha foi salva. Clique abaixo para voltar à tela de entrada."
      );

      $("backToLoginBtn").textContent = "Entrar com a nova senha";

      try {
        await sb.auth.signOut();
      } catch (signOutError) {
        console.warn("Não foi possível encerrar a sessão temporária:", signOutError);
      }
    } catch (error) {
      console.error("Falha na redefinição por código:", error);
      showMessage(recoveryErrorMessage(error), true);
      button.disabled = false;
      button.textContent = originalText;
    } finally {
      setLoading(false);
    }
  });
})();