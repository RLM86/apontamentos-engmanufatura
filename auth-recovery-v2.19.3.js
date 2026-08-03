(() => {
  "use strict";

  const PRIMARY_APP_URL="https://apontamentos-engmanufatura.modulardtc.workers.dev/";
  const cfg=window.APONTA_CONFIG||{};
  const $=id=>document.getElementById(id);

  const validation=$("recoveryValidation");
  const form=$("newPasswordForm");
  const message=$("recoveryMessage");
  const button=$("saveNewPasswordBtn");

  function showMessage(text,error=false){
    message.textContent=text;
    message.classList.toggle("error",error);
    message.hidden=false;
  }

  function showInvalidLink(detail=""){
    validation.innerHTML=
      "<h2>Link inválido ou expirado</h2>"+
      "<p>Solicite um novo e-mail em “Esqueci minha senha” e use somente o link mais recente.</p>";

    if(detail)showMessage(detail,true);
    form.hidden=true;
  }

  const configured=
    /^https:\/\/.+\.supabase\.co$/.test(cfg.supabaseUrl||"")&&
    typeof cfg.supabaseAnonKey==="string"&&
    cfg.supabaseAnonKey.length>30&&
    !cfg.supabaseAnonKey.includes("COLE_");

  if(!configured){
    showInvalidLink("A configuração do Supabase não foi carregada.");
    return;
  }

  const url=new URL(window.location.href);
  const authError=
    url.searchParams.get("error_description")||
    url.searchParams.get("error")||
    new URLSearchParams(url.hash.replace(/^#/,"")).get("error_description")||
    "";

  if(authError){
    showInvalidLink(decodeURIComponent(authError.replace(/\+/g," ")));
    return;
  }

  const sb=window.supabase.createClient(
    cfg.supabaseUrl,
    cfg.supabaseAnonKey,
    {
      auth:{
        detectSessionInUrl:true,
        persistSession:true,
        autoRefreshToken:true,
        flowType:"pkce"
      }
    }
  );

  let recoverySessionReady=false;

  async function validateRecoverySession(){
    try{
      const {data,error}=await sb.auth.getSession();
      if(error)throw error;

      if(data?.session){
        recoverySessionReady=true;
        validation.innerHTML=
          "<h2>Crie sua nova senha</h2>"+
          "<p>Digite a nova senha duas vezes para confirmar.</p>";
        form.hidden=false;
        $("newPassword").focus();
        return;
      }

      window.setTimeout(async()=>{
        const {data:retryData,error:retryError}=await sb.auth.getSession();

        if(retryError||!retryData?.session){
          showInvalidLink();
          return;
        }

        recoverySessionReady=true;
        validation.innerHTML=
          "<h2>Crie sua nova senha</h2>"+
          "<p>Digite a nova senha duas vezes para confirmar.</p>";
        form.hidden=false;
        $("newPassword").focus();
      },1200);
    }catch(error){
      showInvalidLink(error?.message||"Não foi possível validar o link.");
    }
  }

  sb.auth.onAuthStateChange((event,session)=>{
    if(event==="PASSWORD_RECOVERY"||event==="SIGNED_IN"){
      if(session){
        recoverySessionReady=true;
        validation.innerHTML=
          "<h2>Crie sua nova senha</h2>"+
          "<p>Digite a nova senha duas vezes para confirmar.</p>";
        form.hidden=false;
      }
    }
  });

  form.addEventListener("submit",async event=>{
    event.preventDefault();

    const password=$("newPassword").value;
    const confirmation=$("confirmNewPassword").value;

    message.hidden=true;

    if(password.length<6){
      showMessage("A senha deve possuir pelo menos 6 caracteres.",true);
      return;
    }

    if(password!==confirmation){
      showMessage("As senhas informadas não são iguais.",true);
      return;
    }

    if(!recoverySessionReady){
      showMessage(
        "O link ainda não foi validado. Atualize a página ou solicite um novo e-mail.",
        true
      );
      return;
    }

    const originalText=button.textContent;
    button.disabled=true;
    button.textContent="Salvando...";

    try{
      const {error}=await sb.auth.updateUser({password});
      if(error)throw error;

      validation.innerHTML="<h2>Senha atualizada</h2>";
      form.hidden=true;
      showMessage(
        "Sua senha foi alterada com sucesso. Volte para a tela de entrada."
      );

      await sb.auth.signOut();
      $("backToLoginBtn").textContent="Entrar com a nova senha";
    }catch(error){
      showMessage(error?.message||"Não foi possível atualizar a senha.",true);
      button.disabled=false;
      button.textContent=originalText;
    }
  });

  validateRecoverySession();
})();
