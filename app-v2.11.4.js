(() => {
  "use strict";

  const cfg = window.APONTA_CONFIG || {};
  const configured =
    /^https:\/\/.+\.supabase\.co$/.test(cfg.supabaseUrl || "") &&
    typeof cfg.supabaseAnonKey === "string" &&
    cfg.supabaseAnonKey.length > 30 &&
    !cfg.supabaseAnonKey.includes("COLE_");

  const $ = (id) => document.getElementById(id);
  const setupScreen = $("setupScreen");
  const authScreen = $("authScreen");
  const app = $("app");
  const loading = $("loading");

  if (!configured) {
    setupScreen.hidden = false;
    return;
  }

  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
    auth: {
      detectSessionInUrl: true,
      persistSession: true,
      autoRefreshToken: true,
      flowType: "pkce"
    }
  });
  let session = null;
  let me = null;
  let profiles = [];
  let projects = [];
  let activities = [];
  let holidays = [];
  let absences = [];
  let lastReportRows = [];
  let lastPeopleReportRows = [];
  let lastPeopleAbsenceRows = [];
  let currentClosing = null;

  const today = () => new Date().toISOString().slice(0, 10);
  const monthNow = () => today().slice(0, 7);
  const firstDay = (month = monthNow()) => `${month}-01`;
  const nextMonthFirst = (month = monthNow()) => {
    const [y, m] = month.split("-").map(Number);
    return new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10);
  };
  const lastDay = (month = monthNow()) => {
    const [y, m] = month.split("-").map(Number);
    return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
  };
  const fmt = (n) => Number(n || 0).toLocaleString("pt-BR", {minimumFractionDigits: 2, maximumFractionDigits: 2});
  const dateBR = (d) => d ? d.split("-").reverse().join("/") : "—";
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const roleLabel = (r) => ({administrador:"Administrador", gestor:"Gestor", colaborador:"Colaborador"}[r] || r);
  const statusLabel = (s) => ({rascunho:"Rascunho", enviado:"Enviado", aprovado:"Aprovado", devolvido:"Devolvido", aberto:"Aberto"}[s] || s);
  const registrationStatus = (profile = me) => profile?.registration_status || "aprovado";
  const registrationLabel = (status) => ({pendente:"Pendente", aprovado:"Aprovado", rejeitado:"Rejeitado"}[status] || status);
  const canMakeEntries = (profile = me) => Boolean(profile?.active && registrationStatus(profile) === "aprovado");
  const registrationFeatureInstalled = () =>
    profiles.some(profile =>
      Object.prototype.hasOwnProperty.call(profile, "registration_status")
    );
  const absenceTypeLabel = (value) => {
    const raw = String(value || "").trim();
    const key = raw.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    const labels = {
      "ferias":"Férias",
      "atestado":"Atestado médico",
      "atestado medico":"Atestado médico",
      "afastamento":"Afastamento",
      "afastamento pelo inss":"Afastamento pelo INSS",
      "licenca":"Licença",
      "licenca-maternidade":"Licença-maternidade",
      "licenca-paternidade":"Licença-paternidade",
      "licenca nao remunerada":"Licença não remunerada",
      "folga":"Folga",
      "outro":"Outro afastamento",
      "outro afastamento":"Outro afastamento"
    };
    return labels[key] || raw || "—";
  };
  const absenceStatus = (row) => {
    if (today() < row.start_date) return "programado";
    if (today() > row.end_date) return "encerrado";
    return "em_andamento";
  };
  const absenceStatusLabel = (status) => ({programado:"Programado", em_andamento:"Em andamento", encerrado:"Encerrado"}[status] || status);
  const absenceApprovalStatus = (row) => row?.approval_status === "aprovado" ? "aprovado" : "pendente";
  const absenceApprovalLabel = (status) => ({pendente:"Pendente", aprovado:"Aprovado"}[status] || status);
  const absenceDays = (row) => Math.round((new Date(`${row.end_date}T12:00:00`) - new Date(`${row.start_date}T12:00:00`)) / 86400000) + 1;
  const normalizeText = (value) => String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLowerCase();
  const absenceCategory = (value) => {
    const type = normalizeText(absenceTypeLabel(value));
    if (type.includes("ferias")) return "vacation";
    if (type.includes("atestado")) return "medical";
    if (type.includes("afastamento") || type.includes("licenca")) return "away";
    if (type.includes("folga")) return "dayoff";
    return "other";
  };
  const overlapDays = (row, start, end) => {
    const overlapStart = row.start_date > start ? row.start_date : start;
    const overlapEnd = row.end_date < end ? row.end_date : end;
    if (overlapEnd < overlapStart) return 0;
    return Math.round((new Date(`${overlapEnd}T12:00:00`) - new Date(`${overlapStart}T12:00:00`)) / 86400000) + 1;
  };
  const isFutureDate = (value) => Boolean(value && value > today());
  const validateNotFutureDate = (value, fieldName = "data") => {
    if (!isFutureDate(value)) return true;
    toast(`Não é permitido informar ${fieldName} futura. A data máxima é ${dateBR(today())}.`, true);
    return false;
  };
  const isManager = () => ["administrador","gestor"].includes(me?.role);
  const isAdmin = () => me?.role === "administrador";
  const showLoading = (on) => loading.hidden = !on;
  const appBaseUrl = () => {
    const url = new URL(window.location.href);
    url.search = "";
    url.hash = "";
    url.pathname = url.pathname.endsWith("/") ? url.pathname : url.pathname.replace(/[^/]*$/, "");
    return url.href;
  };

  function showAuthMessage(message, error = false) {
    const box = $("authMessage");
    box.textContent = message;
    box.classList.toggle("error", error);
    box.hidden = false;
  }

  function clearAuthMessage() {
    $("authMessage").hidden = true;
    $("authMessage").textContent = "";
  }

  function toast(message, error = false) {
    const el = $("toast");
    el.textContent = message;
    el.style.background = error ? "#b42318" : "#101828";
    el.hidden = false;
    clearTimeout(window.__toastTimer);
    window.__toastTimer = setTimeout(() => el.hidden = true, 3500);
  }

  function handleError(error, fallback = "Não foi possível concluir a operação.") {
    console.error(error);
    toast(error?.message || fallback, true);
  }

  function profileName(id) {
    return profiles.find(p => p.id === id)?.full_name || "—";
  }
  function projectName(id) {
    return projects.find(p => p.id === id)?.name || "—";
  }
  function activityName(id) {
    return activities.find(a => a.id === id)?.name || "—";
  }

  async function loadBaseData() {
    const [p, pr, ac, ho] = await Promise.all([
      sb.from("profiles").select("*").order("full_name"),
      sb.from("projects").select("*").order("name"),
      sb.from("activities").select("*").order("name"),
      sb.from("holidays").select("*").order("holiday_date")
    ]);
    if (p.error) throw p.error;
    if (pr.error) throw pr.error;
    if (ac.error) throw ac.error;
    if (ho.error) throw ho.error;
    profiles = p.data || [];
    projects = pr.data || [];
    activities = ac.data || [];
    holidays = ho.data || [];
    me = profiles.find(x => x.id === session.user.id);
    if (!me) throw new Error("Seu perfil ainda não foi criado. Atualize a página em alguns segundos.");
    if (!me.active) throw new Error("Seu usuário está inativo. Fale com o administrador.");
    applyPermissions();
    fillSelects();
  }

  function applyPermissions() {
    document.querySelectorAll("[data-manager-only]").forEach(el => el.hidden = !isManager());
    document.querySelectorAll("[data-admin-only]").forEach(el => el.hidden = !isAdmin());
    document.querySelectorAll(".manager-user-field").forEach(el => el.hidden = !isManager());

    const entryApproved = canMakeEntries();
    document.querySelectorAll("[data-entry-approval-required]").forEach(el => {
      el.hidden = !entryApproved;
    });

    $("currentUser").textContent = me.full_name;
    $("currentRole").textContent = roleLabel(me.role);

    const currentRegistration = $("currentRegistration");
    if (currentRegistration) {
      const status = registrationStatus();
      currentRegistration.textContent = registrationLabel(status);
      currentRegistration.className = `badge registration-top-badge registration-${status}`;
    }

    const banner = $("registrationApprovalBanner");
    if (banner) {
      const status = registrationStatus();
      banner.hidden = entryApproved;

      if (!entryApproved) {
        const rejected = status === "rejeitado";
        $("registrationApprovalTitle").textContent = rejected
          ? "Cadastro não autorizado para apontamentos"
          : "Cadastro pendente de aprovação";
        $("registrationApprovalMessage").textContent = rejected
          ? "Um Gestor ou Administrador rejeitou a liberação. Procure a liderança para solicitar uma nova análise."
          : "Um Gestor ou Administrador precisa liberar seu acesso antes do primeiro apontamento.";
        $("registrationApprovalBadge").textContent = registrationLabel(status);
        $("registrationApprovalBadge").className = `badge registration-${status}`;
      }
    }
  }

  function optionList(rows, blank = false, activeOnly = false) {
    const filtered = activeOnly ? rows.filter(x => x.active) : rows;
    return (blank ? '<option value="">Todos</option>' : "") +
      filtered.map(x => `<option value="${x.id}">${esc(x.full_name || x.name)}</option>`).join("");
  }

  function fillSelects() {
    const activeProfiles = profiles.filter(p => p.active);
    const approvedProfiles = activeProfiles.filter(p => canMakeEntries(p));

    ["entryUser","closingUser"].forEach(id => {
      const el = $(id);
      const old = el.value;
      el.innerHTML = optionList(approvedProfiles);
      el.value = isManager() ? (old || me.id) : me.id;
      if (!isManager()) el.disabled = true;
    });

    ["absenceUser"].forEach(id => {
      const el = $(id);
      const old = el.value;
      el.innerHTML = optionList(activeProfiles);
      el.value = isManager() ? (old || me.id) : me.id;
      if (!isManager()) el.disabled = true;
    });

    ["filterEntryUser","reportUser","absenceFilterUser","peopleReportUser"].forEach(id => {
      const el = $(id);
      if (!el) return;
      const old = el.value;
      el.innerHTML = optionList(activeProfiles, true);
      el.value = isManager() ? old : me.id;
      if (!isManager()) el.disabled = true;
    });

    $("entryProject").innerHTML = optionList(projects, false, true);
    $("editEntryProject").innerHTML = optionList(projects, false, true);
    $("reportProject").innerHTML = optionList(projects, true);
    $("entryActivity").innerHTML = optionList(activities, false, true);
    $("editEntryActivity").innerHTML = optionList(activities, false, true);
  }

  function setInitialDates() {
    $("entryDate").max = today();
    $("editEntryDate").max = today();
    $("entryDate").value ||= today();
    $("absenceStart").value ||= today();
    $("absenceEnd").value ||= today();
    $("filterEntryStart").value ||= firstDay();
    $("filterEntryEnd").value ||= lastDay();
    $("reportStart").value ||= firstDay();
    $("reportEnd").value ||= lastDay();
    $("peopleReportStart").value ||= firstDay();
    $("peopleReportEnd").value ||= lastDay();
    $("closingMonth").value ||= monthNow();
  }

  async function showApp() {
    showLoading(true);
    try {
      await loadBaseData();
      authScreen.hidden = true;
      setupScreen.hidden = true;
      app.hidden = false;
      setInitialDates();
      renderProfile();
      await Promise.all([renderDashboard(), renderEntries(), renderAbsences(), renderCatalogs(), renderTeam(), loadClosing(), renderReport(), renderPeopleReport()]);
    } catch (e) {
      await sb.auth.signOut();
      authScreen.hidden = false;
      app.hidden = true;
      handleError(e);
    } finally {
      showLoading(false);
    }
  }

  async function boot() {
    authScreen.hidden = false;
    const params = new URLSearchParams(window.location.search);
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
    const authError = params.get("error_description") || hash.get("error_description") || params.get("error") || hash.get("error");
    const code = params.get("code");

    if (authError) {
      showAuthMessage(
        "O aplicativo recebeu um retorno antigo de confirmação de e-mail.\n\n" +
        decodeURIComponent(authError) +
        "\n\nConfira no Supabase se a URL exata deste aplicativo está cadastrada em Authentication → URL Configuration.",
        true
      );
      history.replaceState({}, document.title, appBaseUrl());
    }

    if (code) {
      showLoading(true);
      try {
        const {data, error} = await sb.auth.exchangeCodeForSession(code);
        if (error) throw error;
        session = data.session;
        history.replaceState({}, document.title, appBaseUrl());
        showAuthMessage("Sessão validada. Abrindo o aplicativo...");
      } catch (error) {
        showAuthMessage(
          "O link de autenticação não pôde ser concluído. Faça o login normalmente com e-mail e senha.",
          true
        );
        history.replaceState({}, document.title, appBaseUrl());
      } finally {
        showLoading(false);
      }
    }

    if (!session) {
      const {data, error} = await sb.auth.getSession();
      if (error) handleError(error);
      session = data.session;
    }

    if (session) await showApp();
    else authScreen.hidden = false;
  }

  document.querySelectorAll("[data-auth-tab]").forEach(btn => {
    btn.onclick = () => {
      clearAuthMessage();
      document.querySelectorAll("[data-auth-tab]").forEach(x => x.classList.toggle("active", x === btn));
      $("loginForm").classList.toggle("active", btn.dataset.authTab === "login");
      $("signupForm").classList.toggle("active", btn.dataset.authTab === "signup");
    };
  });

  $("loginForm").onsubmit = async (e) => {
    e.preventDefault(); showLoading(true);
    try {
      const {data, error} = await sb.auth.signInWithPassword({email:$("loginEmail").value.trim(), password:$("loginPassword").value});
      if (error) throw error;
      session = data.session;
      await showApp();
    } catch (e2) { handleError(e2, "E-mail ou senha inválidos."); }
    finally { showLoading(false); }
  };

  $("signupForm").onsubmit = async (e) => {
    e.preventDefault(); showLoading(true);
    try {
      const {data, error} = await sb.auth.signUp({
        email:$("signupEmail").value.trim(),
        password:$("signupPassword").value,
        options:{data:{full_name:$("signupName").value.trim()}}
      });
      if (error) throw error;

      if (!data.session) {
        document.querySelector('[data-auth-tab="login"]').click();
        $("loginEmail").value = $("signupEmail").value.trim();
        showAuthMessage(
          "A conta foi criada, mas a confirmação de e-mail ainda está ativada no Supabase. " +
          "Desative “Confirm email” em Authentication → Providers → Email para usar a aprovação por Gestor/Administrador.",
          true
        );
        return;
      }

      session = data.session;
      await showApp();
      toast("Conta criada. Aguarde a aprovação de um Gestor ou Administrador.");
    } catch (e2) { handleError(e2); }
    finally { showLoading(false); }
  };

  $("forgotPasswordBtn").onclick = async () => {
    const email = $("loginEmail").value.trim() || prompt("Informe seu e-mail:");
    if (!email) return;
    const {error} = await sb.auth.resetPasswordForEmail(email, {redirectTo: appBaseUrl()});
    if (error) handleError(error); else showAuthMessage("E-mail de recuperação enviado.");
  };


  $("logoutBtn").onclick = async () => { await sb.auth.signOut(); location.reload(); };

  $("mainNav").onclick = async (e) => {
    const btn = e.target.closest("button[data-page]");
    if (!btn) return;
    if (btn.hasAttribute("data-entry-approval-required") && !canMakeEntries()) {
      toast("Aguarde a aprovação do Gestor ou Administrador para acessar os apontamentos.", true);
      return;
    }
    document.querySelectorAll("#mainNav button").forEach(x => x.classList.toggle("active", x === btn));
    document.querySelectorAll(".page").forEach(x => x.classList.toggle("active", x.id === btn.dataset.page));
    if (btn.dataset.page === "dashboard") await renderDashboard();
    if (btn.dataset.page === "entries") await renderEntries();
    if (btn.dataset.page === "absences") await renderAbsences();
    if (btn.dataset.page === "reports") await renderActiveReport();
    if (btn.dataset.page === "profile") renderProfile();
    if (btn.dataset.page === "catalogs") await renderCatalogs();
    if (btn.dataset.page === "importExcel") renderExcelImportPage();
    if (btn.dataset.page === "backupRestore") renderBackupPage();
    if (btn.dataset.page === "team") await renderTeam();
  };


  document.querySelectorAll("[data-page-jump]").forEach((button) => {
    button.addEventListener("click", async () => {
      const page = button.dataset.pageJump;
      const navButton = document.querySelector(`#mainNav button[data-page="${page}"]`);
      if (navButton) navButton.click();
    });
  });

  async function selectEntries(start, end, userId = "", projectId = "") {
    let q = sb.from("time_entries").select("*").gte("entry_date", start).lte("entry_date", end).order("entry_date", {ascending:false});
    if (userId) q = q.eq("user_id", userId);
    if (projectId) q = q.eq("project_id", projectId);
    const {data, error} = await q;
    if (error) throw error;
    return data || [];
  }

  async function selectAbsencesForReport(start, end, userId = "", typeFilter = "") {
    let q = sb.from("absences").select("*").lte("start_date", end).gte("end_date", start).order("start_date", {ascending:false});
    if (userId) q = q.eq("user_id", userId);
    const {data, error} = await q;
    if (error) throw error;
    const normalizedFilter = normalizeText(typeFilter);
    return (data || []).filter(row => {
      if (!normalizedFilter) return true;
      return normalizeText(absenceTypeLabel(row.absence_type)).includes(normalizedFilter);
    });
  }

  async function renderDashboard() {
    try {
      const start = firstDay(), end = lastDay();
      const rows = await selectEntries(start, end, isManager() ? "" : me.id);
      $("dashboardPeriod").textContent = `Período de ${dateBR(start)} a ${dateBR(end)}`;
      $("metricHours").textContent = fmt(rows.reduce((s,x)=>s+Number(x.hours),0));
      $("metricEntries").textContent = rows.length;
      $("metricUsers").textContent = isManager() ? profiles.filter(x=>x.active&&canMakeEntries(x)).length : 1;
      $("metricProjects").textContent = projects.filter(x=>x.active).length;

      const byUser = {};
      rows.forEach(x => byUser[x.user_id] = (byUser[x.user_id] || 0) + Number(x.hours));
      $("dashboardUsers").innerHTML = Object.entries(byUser)
        .sort((a,b)=>b[1]-a[1])
        .map(([id,h])=>`<tr><td>${esc(profileName(id))}</td><td>${fmt(h)}</td></tr>`).join("") ||
        '<tr><td colspan="2" class="empty">Sem lançamentos no período</td></tr>';

      const byProject = {};
      rows.forEach(x => byProject[x.project_id] = (byProject[x.project_id] || 0) + Number(x.hours));
      $("dashboardProjects").innerHTML = Object.entries(byProject)
        .sort((a,b)=>b[1]-a[1])
        .map(([id,h])=>`<tr><td>${esc(projectName(id))}</td><td>${fmt(h)}</td></tr>`).join("") ||
        '<tr><td colspan="2" class="empty">Sem lançamentos no período</td></tr>';
    } catch (e) { handleError(e); }
  }

  $("refreshDashboard").onclick = renderDashboard;

  async function getDayHours(userId, entryDate) {
    const rows = await selectEntries(entryDate, entryDate, userId);
    return rows.reduce((sum, item) => sum + Number(item.hours), 0);
  }

  async function updateDayTotal() {
    try {
      const userId = isManager() ? $("entryUser").value : me.id;
      const entryDate = $("entryDate").value;
      const box = $("dayTotal");

      if (!userId || !entryDate) {
        box.textContent = "";
        box.className = "day-total";
        return;
      }

      if (isFutureDate(entryDate)) {
        box.textContent = `DATA FUTURA BLOQUEADA: escolha uma data até ${dateBR(today())}.`;
        box.className = "day-total day-total-exceeded";
        return;
      }

      const registeredHours = await getDayHours(userId, entryDate);
      const newHours = Number($("entryHours").value || 0);
      const projectedHours = registeredHours + newHours;
      const dailyHours = Number(profiles.find(x => x.id === userId)?.daily_hours || 8);
      const difference = dailyHours - projectedHours;

      box.className = "day-total";

      if (newHours > 0) {
        box.textContent =
          `Já apontado: ${fmt(registeredHours)} h · Novo lançamento: ${fmt(newHours)} h · ` +
          `Total previsto: ${fmt(projectedHours)} h · ` +
          (difference > 0
            ? `Ainda restam ${fmt(difference)} h`
            : difference === 0
              ? "Jornada prevista completa"
              : `ATENÇÃO: excederá a jornada em ${fmt(-difference)} h`);
      } else {
        box.textContent =
          `Total do dia: ${fmt(registeredHours)} h · ` +
          (difference > 0
            ? `Faltam ${fmt(difference)} h`
            : difference === 0
              ? "Jornada prevista completa"
              : `ATENÇÃO: jornada excedida em ${fmt(-difference)} h`);
      }

      if (difference < 0) {
        box.classList.add("day-total-exceeded");
      } else if (difference === 0) {
        box.classList.add("day-total-complete");
      } else {
        box.classList.add("day-total-pending");
      }
    } catch (error) {
      handleError(error);
    }
  }

  $("entryDate").onchange = async () => {
    if (isFutureDate($("entryDate").value)) {
      $("entryDate").value = today();
      toast(`Datas futuras não são permitidas. A data foi ajustada para ${dateBR(today())}.`, true);
    }
    await updateDayTotal();
  };
  $("entryUser").onchange = updateDayTotal;
  $("entryHours").oninput = updateDayTotal;

  $("entryForm").onsubmit = async (e) => {
    e.preventDefault();

    if (!canMakeEntries()) {
      toast("Seu cadastro ainda não foi aprovado para realizar apontamentos.", true);
      return;
    }

    const entryDate = $("entryDate").value;
    if (!validateNotFutureDate(entryDate, "uma data")) {
      $("entryDate").focus();
      await updateDayTotal();
      return;
    }

    showLoading(true);

    try {
      const userId = isManager() ? $("entryUser").value : me.id;
      const targetProfile = profiles.find(profile => profile.id === userId);
      if (!canMakeEntries(targetProfile)) {
        throw new Error("O colaborador selecionado ainda não está aprovado para realizar apontamentos.");
      }
      const hoursToAdd = Number($("entryHours").value);
      const registeredHours = await getDayHours(userId, entryDate);
      const dailyHours = Number(profiles.find(x => x.id === userId)?.daily_hours || 8);
      const projectedHours = registeredHours + hoursToAdd;
      const exceededHours = projectedHours - dailyHours;

      if (exceededHours > 0) {
        showLoading(false);

        const confirmed = window.confirm(
          `ATENÇÃO: JORNADA DIÁRIA EXCEDIDA\n\n` +
          `Jornada prevista: ${fmt(dailyHours)} h\n` +
          `Horas já apontadas: ${fmt(registeredHours)} h\n` +
          `Novo lançamento: ${fmt(hoursToAdd)} h\n` +
          `Total após salvar: ${fmt(projectedHours)} h\n` +
          `Excedente: ${fmt(exceededHours)} h\n\n` +
          `Deseja salvar mesmo assim?`
        );

        if (!confirmed) {
          await updateDayTotal();
          return;
        }

        showLoading(true);
      }

      const payload = {
        user_id: userId,
        entry_date: entryDate,
        project_id: $("entryProject").value,
        activity_id: $("entryActivity").value,
        hours: hoursToAdd,
        details: $("entryDetails").value.trim(),
        status: "rascunho"
      };

      const {error} = await sb.from("time_entries").insert(payload);
      if (error) throw error;

      $("entryHours").value = "";
      $("entryDetails").value = "";

      if (exceededHours > 0) {
        toast(`Apontamento salvo. Jornada excedida em ${fmt(exceededHours)} h.`, true);
      } else {
        toast("Apontamento salvo.");
      }

      await Promise.all([renderEntries(), renderDashboard(), updateDayTotal()]);
    } catch (error) {
      handleError(error);
    } finally {
      showLoading(false);
    }
  };

  async function renderEntries() {
    try {
      const user = isManager() ? $("filterEntryUser").value : me.id;
      const rows = await selectEntries($("filterEntryStart").value || firstDay(), $("filterEntryEnd").value || lastDay(), user);
      $("entriesTable").innerHTML = rows.map(x => {
        const editable = isManager() || (x.user_id === me.id && ["rascunho","devolvido"].includes(x.status));
        return `<tr>
          <td>${dateBR(x.entry_date)}</td><td>${esc(profileName(x.user_id))}</td>
          <td>${esc(projectName(x.project_id))}</td><td>${esc(activityName(x.activity_id))}</td>
          <td>${fmt(x.hours)}</td><td><span class="badge status-${x.status}">${statusLabel(x.status)}</span></td>
          <td>${editable ? `<button class="btn secondary small" data-edit-entry="${x.id}">Editar</button> <button class="btn danger small" data-delete-entry="${x.id}">Excluir</button>` : "—"}</td>
        </tr>`;
      }).join("") || '<tr><td colspan="7" class="empty">Nenhum apontamento encontrado</td></tr>';
      await updateDayTotal();
    } catch (e) { handleError(e); }
  }

  $("filterEntriesBtn").onclick = renderEntries;

  $("entriesTable").onclick = async (e) => {
    const editId = e.target.dataset.editEntry;
    const deleteId = e.target.dataset.deleteEntry;
    if (editId) {
      const {data, error} = await sb.from("time_entries").select("*").eq("id", editId).single();
      if (error) return handleError(error);
      $("editEntryId").value = data.id;
      $("editEntryDate").value = data.entry_date;
      $("editEntryHours").value = data.hours;
      $("editEntryProject").value = data.project_id;
      $("editEntryActivity").value = data.activity_id;
      $("editEntryDetails").value = data.details;
      $("editEntryDialog").showModal();
    }
    if (deleteId && confirm("Excluir este apontamento?")) {
      showLoading(true);
      try {
        const {error} = await sb.rpc("aponta_delete_time_entry_v28", {p_id: deleteId});
        if (error) throw error;
        toast("Apontamento excluído.");
        await Promise.all([renderEntries(), renderDashboard()]);
      } catch(error) {
        handleError(error, "Não foi possível excluir. Períodos enviados ou aprovados precisam ser reabertos.");
      } finally { showLoading(false); }
    }
  };

  $("saveEditEntryBtn").onclick = async (e) => {
    e.preventDefault();

    const editedDate = $("editEntryDate").value;
    if (!validateNotFutureDate(editedDate, "uma data")) {
      $("editEntryDate").focus();
      return;
    }

    showLoading(true);
    try {
      const {error} = await sb.from("time_entries").update({
        entry_date:editedDate, hours:Number($("editEntryHours").value),
        project_id:$("editEntryProject").value, activity_id:$("editEntryActivity").value,
        details:$("editEntryDetails").value.trim(), status:"rascunho"
      }).eq("id",$("editEntryId").value);
      if (error) throw error;
      $("editEntryDialog").close(); toast("Apontamento atualizado.");
      await Promise.all([renderEntries(),renderDashboard()]);
    } catch(e2){handleError(e2)} finally{showLoading(false)}
  };

  $("copyPreviousBtn").onclick = async () => {
    const userId = isManager() ? $("entryUser").value : me.id;
    const target = $("entryDate").value;
    if (!userId || !target) return;

    if (!validateNotFutureDate(target, "uma data")) {
      $("entryDate").value = today();
      await updateDayTotal();
      return;
    }

    showLoading(true);
    try {
      const {data:previous,error} = await sb.from("time_entries").select("*")
        .eq("user_id",userId).lt("entry_date",target).order("entry_date",{ascending:false}).limit(1);
      if (error) throw error;
      if (!previous?.length) return toast("Não há dia anterior para copiar.", true);
      const sourceDate = previous[0].entry_date;
      const {data:source,error:sourceError} = await sb.from("time_entries").select("*").eq("user_id",userId).eq("entry_date",sourceDate);
      if (sourceError) throw sourceError;
      const copies = source.map(x=>({user_id:userId,entry_date:target,project_id:x.project_id,activity_id:x.activity_id,hours:x.hours,details:x.details,status:"rascunho"}));
      const {error:insertError} = await sb.from("time_entries").insert(copies);
      if (insertError) throw insertError;
      toast(`${copies.length} apontamento(s) copiado(s) de ${dateBR(sourceDate)}.`);
      await Promise.all([renderEntries(),renderDashboard()]);
    } catch(e){handleError(e)} finally{showLoading(false)}
  };

  function resetAbsenceForm() {
    $("absenceId").value = "";
    $("absenceFormTitle").textContent = "Novo período";
    $("saveAbsenceBtn").textContent = "Salvar período";
    $("cancelAbsenceEditBtn").hidden = true;
    $("absenceType").value = "Férias";
    $("absenceStart").value = today();
    $("absenceEnd").value = today();
    $("absenceNotes").value = "";
  }

  $("cancelAbsenceEditBtn").onclick = resetAbsenceForm;

  $("absenceForm").onsubmit = async (e) => {
    e.preventDefault();
    if ($("absenceEnd").value < $("absenceStart").value) return toast("A data final não pode ser menor que a inicial.", true);
    showLoading(true);
    try {
      const {error} = await sb.rpc("aponta_upsert_absence_v28", {
        p_id: $("absenceId").value || null,
        p_user_id: isManager() ? $("absenceUser").value : me.id,
        p_absence_type: $("absenceType").value,
        p_start_date: $("absenceStart").value,
        p_end_date: $("absenceEnd").value,
        p_notes: $("absenceNotes").value.trim()
      });
      if (error) throw error;
      const edited = Boolean($("absenceId").value);
      resetAbsenceForm();
      toast(edited ? "Período atualizado." : (isManager() ? "Período cadastrado como pendente de aprovação." : "Período enviado para aprovação do gestor."));
      await renderAbsences();
    } catch(error){
      handleError(error, "Não foi possível salvar. Execute o SQL da versão 2.8 no Supabase.");
    } finally { showLoading(false); }
  };

  function renderAbsenceRows() {
    const userFilter = isManager() ? $("absenceFilterUser").value : me.id;
    const typeFilter = $("absenceFilterType").value;
    const statusFilter = $("absenceFilterStatus").value;
    const approvalFilter = $("absenceFilterApproval").value;
    const normalizedFilter = typeFilter.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

    const rows = absences.filter(x => {
      const normalizedType = absenceTypeLabel(x.absence_type).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
      return (!userFilter || x.user_id === userFilter) &&
        (!normalizedFilter || normalizedType.includes(normalizedFilter)) &&
        (!statusFilter || absenceStatus(x) === statusFilter) &&
        (!approvalFilter || absenceApprovalStatus(x) === approvalFilter);
    });

    $("absencesTable").innerHTML = rows.map(x => {
      const status = absenceStatus(x);
      const approval = absenceApprovalStatus(x);
      const userCanModify = isManager() || approval !== "aprovado";
      const approvalAction = isManager() && approval === "pendente"
        ? `<button class="btn success small" data-approve-absence="${x.id}">Aprovar</button>`
        : "";
      const editActions = userCanModify
        ? `<button class="btn secondary small" data-edit-absence="${x.id}">Editar</button><button class="btn danger small" data-delete-absence="${x.id}">Excluir</button>`
        : '<span class="badge approval-locked">Bloqueado</span>';
      return `<tr>
        <td>${esc(profileName(x.user_id))}</td>
        <td>${dateBR(x.start_date)} a ${dateBR(x.end_date)}</td>
        <td>${absenceDays(x)}</td>
        <td>${esc(absenceTypeLabel(x.absence_type))}</td>
        <td><span class="badge absence-${status}">${absenceStatusLabel(status)}</span></td>
        <td><span class="badge approval-${approval}">${absenceApprovalLabel(approval)}</span></td>
        <td>${esc(x.notes || "—")}</td>
        <td><div class="table-actions">${approvalAction}${editActions}</div></td>
      </tr>`;
    }).join("") || '<tr><td colspan="8" class="empty">Nenhum período encontrado</td></tr>';
  }

  async function renderAbsences() {
    try {
      let q = sb.from("absences").select("*").order("start_date", {ascending:false});
      if (!isManager()) q = q.eq("user_id", me.id);
      const {data,error} = await q;
      if (error) throw error;
      absences = data || [];
      renderAbsenceRows();
    } catch(error) { handleError(error); }
  }

  $("absenceFilterUser").onchange = renderAbsenceRows;
  $("absenceFilterType").onchange = renderAbsenceRows;
  $("absenceFilterStatus").onchange = renderAbsenceRows;
  $("absenceFilterApproval").onchange = renderAbsenceRows;

  $("absencesTable").onclick = async (e) => {
    const editId = e.target.dataset.editAbsence;
    const deleteId = e.target.dataset.deleteAbsence;
    const approveId = e.target.dataset.approveAbsence;

    if (approveId) {
      if (!isManager()) return toast("Somente Gestor ou Administrador pode aprovar.", true);
      if (!confirm("Aprovar este período? Após a aprovação, o colaborador não poderá editar nem excluir.")) return;
      showLoading(true);
      try {
        const {error} = await sb.rpc("aponta_approve_absence_v210", {p_id: approveId});
        if (error) throw error;
        toast("Férias/afastamento aprovado. O registro foi bloqueado para o colaborador.");
        await renderAbsences();
      } catch(error) {
        handleError(error, "Não foi possível aprovar. Execute o SQL da versão 2.10 no Supabase.");
      } finally { showLoading(false); }
      return;
    }

    if (editId) {
      const row = absences.find(x => x.id === editId);
      if (!row) return;
      if (!isManager() && absenceApprovalStatus(row) === "aprovado") {
        return toast("Este período já foi aprovado. Somente Gestor ou Administrador pode alterá-lo.", true);
      }
      $("absenceId").value = row.id;
      if (isManager()) $("absenceUser").value = row.user_id;
      $("absenceStart").value = row.start_date;
      $("absenceEnd").value = row.end_date;
      const label = absenceTypeLabel(row.absence_type);
      const validOption = [...$("absenceType").options].some(option => option.value === label);
      $("absenceType").value = validOption ? label : "Outro afastamento";
      $("absenceNotes").value = row.notes || "";
      $("absenceFormTitle").textContent = "Editar período";
      $("saveAbsenceBtn").textContent = "Salvar alteração";
      $("cancelAbsenceEditBtn").hidden = false;
      $("absenceForm").scrollIntoView({behavior:"smooth", block:"start"});
    }

    if (deleteId) {
      const row = absences.find(x => x.id === deleteId);
      if (row && !isManager() && absenceApprovalStatus(row) === "aprovado") {
        return toast("Este período já foi aprovado. Somente Gestor ou Administrador pode excluí-lo.", true);
      }
    }

    if (deleteId && confirm("Excluir este período de férias/afastamento?")) {
      showLoading(true);
      try {
        const {error} = await sb.rpc("aponta_delete_absence_v28", {p_id: deleteId});
        if (error) throw error;
        if ($("absenceId").value === deleteId) resetAbsenceForm();
        toast("Período excluído.");
        await renderAbsences();
      } catch(error) {
        handleError(error, "Não foi possível excluir. Execute o SQL da versão 2.8 no Supabase.");
      } finally { showLoading(false); }
    }
  };

  async function loadClosing() {
    try {
      const userId=isManager()?$("closingUser").value:me.id, month=$("closingMonth").value||monthNow();
      if(!userId)return;
      const rows=await selectEntries(firstDay(month),lastDay(month),userId);
      $("closingHours").textContent=fmt(rows.reduce((s,x)=>s+Number(x.hours),0));
      const {data,error}=await sb.from("monthly_closings").select("*").eq("user_id",userId).eq("month_ref",firstDay(month)).maybeSingle();
      if(error)throw error;
      currentClosing=data;
      $("closingStatus").textContent=statusLabel(data?.status||"aberto");
      $("closingNote").value=data?.review_note||"";
      $("submitClosingBtn").disabled=!!data&&["enviado","aprovado"].includes(data.status);
      $("approveClosingBtn").disabled=!data||data.status!=="enviado";
      $("rejectClosingBtn").disabled=!data||data.status!=="enviado";
    }catch(e){handleError(e)}
  }
  $("loadClosingBtn").onclick=loadClosing;$("closingUser").onchange=loadClosing;$("closingMonth").onchange=loadClosing;

  async function readFunctionError(error) {
    let message = error?.message || "Falha ao chamar a função de e-mail.";
    let code = "";

    try {
      const response = error?.context;
      if (response && typeof response.clone === "function") {
        const payload = await response.clone().json();
        if (payload?.error) message = payload.error;
        if (payload?.code) code = payload.code;
      }
    } catch (_) {}

    if (/Failed to send a request|not found|404/i.test(message)) {
      message =
        "A função enviar-aprovacao não foi encontrada ou não está publicada no Supabase.";
      code = "FUNCTION_NOT_DEPLOYED";
    }

    const detailedError = new Error(message);
    detailedError.code = code;
    return detailedError;
  }

  async function sendApprovalEmail(userId, month) {
    const {data, error} = await sb.functions.invoke("enviar-aprovacao", {
      body: {userId, month}
    });

    if (error) {
      throw await readFunctionError(error);
    }

    if (!data?.sent) {
      const detailedError = new Error(
        data?.error || "O serviço não confirmou o envio do e-mail."
      );
      detailedError.code = data?.code || "";
      throw detailedError;
    }

    return data;
  }

  $("submitClosingBtn").onclick=async()=>{
    const userId=isManager()?$("closingUser").value:me.id;
    const targetProfile=profiles.find(profile=>profile.id===userId);
    if(!canMakeEntries(targetProfile)){
      toast("Este colaborador ainda não está aprovado para realizar apontamentos.",true);
      return;
    }
    const monthValue=$("closingMonth").value;
    const month=firstDay(monthValue);
    let emailResult=null;
    let emailError=null;

    showLoading(true);

    try{
      const{error}=await sb.from("monthly_closings").upsert({
        user_id:userId,
        month_ref:month,
        status:"enviado",
        submitted_at:new Date().toISOString(),
        review_note:""
      },{onConflict:"user_id,month_ref"});

      if(error)throw error;

      const{error:e2}=await sb.from("time_entries")
        .update({status:"enviado"})
        .eq("user_id",userId)
        .gte("entry_date",month)
        .lt("entry_date",nextMonthFirst(monthValue))
        .in("status",["rascunho","devolvido"]);

      if(e2)throw e2;

      try {
        emailResult = await sendApprovalEmail(userId, month);
      } catch (mailError) {
        emailError = mailError;
        console.error("Falha ao enviar e-mail de aprovação:", mailError);
      }

      await Promise.all([loadClosing(),renderEntries(),renderDashboard()]);

      if (emailError) {
        toast(
          `Mês enviado para aprovação. O e-mail não foi enviado: ${emailError.message}`,
          true
        );
      } else {
        const count = Number(emailResult?.recipients || 0);
        toast(
          `Mês enviado para aprovação. E-mail enviado para ${count} ${count === 1 ? "aprovador" : "aprovadores"}.`
        );
      }
    }catch(e){
      handleError(e);
    }finally{
      showLoading(false);
    }
  };

  async function reviewClosing(status){
    if(!isManager()||!currentClosing)return;
    showLoading(true);
    try{
      const userId=$("closingUser").value, month=$("closingMonth").value;
      const{error}=await sb.from("monthly_closings").update({status,reviewed_by:me.id,reviewed_at:new Date().toISOString(),review_note:$("closingNote").value.trim()}).eq("id",currentClosing.id);
      if(error)throw error;
      const entryStatus=status==="aprovado"?"aprovado":"devolvido";
      const{error:e2}=await sb.from("time_entries").update({status:entryStatus}).eq("user_id",userId).gte("entry_date",firstDay(month)).lt("entry_date",nextMonthFirst(month)).eq("status","enviado");
      if(e2)throw e2;
      toast(status==="aprovado"?"Fechamento aprovado.":"Fechamento devolvido.");
      await Promise.all([loadClosing(),renderEntries(),renderDashboard()]);
    }catch(e){handleError(e)}finally{showLoading(false)}
  }
  $("approveClosingBtn").onclick=()=>reviewClosing("aprovado");
  $("rejectClosingBtn").onclick=()=>reviewClosing("devolvido");

  function downloadCsv(filename, lines) {
    const csv="\uFEFF"+lines.map(row=>row.map(value=>`"${String(value??"").replaceAll('"','""')}"`).join(";")).join("\n");
    const link=document.createElement("a");
    link.href=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"}));
    link.download=filename;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  async function renderReport(){
    try{
      const user=isManager()?$("reportUser").value:me.id;
      lastReportRows=await selectEntries($("reportStart").value||firstDay(),$("reportEnd").value||lastDay(),user,$("reportProject").value);
      $("reportTotal").textContent=`${fmt(lastReportRows.reduce((s,x)=>s+Number(x.hours),0))} horas`;
      $("reportTable").innerHTML=lastReportRows.map(x=>`<tr><td>${dateBR(x.entry_date)}</td><td>${esc(profileName(x.user_id))}</td><td>${esc(projectName(x.project_id))}</td><td>${esc(activityName(x.activity_id))}</td><td>${fmt(x.hours)}</td><td>${esc(x.details)}</td><td><span class="badge status-${x.status}">${statusLabel(x.status)}</span></td></tr>`).join("")||'<tr><td colspan="7" class="empty">Sem dados</td></tr>';
    }catch(e){handleError(e)}
  }

  async function renderPeopleReport(){
    try{
      const start=$("peopleReportStart").value||firstDay();
      const end=$("peopleReportEnd").value||lastDay();
      if(end<start) return toast("A data final do relatório não pode ser menor que a inicial.",true);

      const user=isManager()?$("peopleReportUser").value:me.id;
      const typeFilter=$("peopleReportType").value;
      const [entries,absenceRows]=await Promise.all([
        selectEntries(start,end,user),
        selectAbsencesForReport(start,end,user,typeFilter)
      ]);

      lastPeopleAbsenceRows=absenceRows.map(row=>({...row,days_in_filter:overlapDays(row,start,end)}));

      const relevantIds=new Set();
      if(user) relevantIds.add(user);
      entries.forEach(row=>relevantIds.add(row.user_id));
      lastPeopleAbsenceRows.forEach(row=>relevantIds.add(row.user_id));
      if(!user&&isManager()) profiles.filter(profile=>profile.active).forEach(profile=>relevantIds.add(profile.id));
      if(!isManager()) relevantIds.add(me.id);

      lastPeopleReportRows=[...relevantIds].map(userId=>{
        const userEntries=entries.filter(row=>row.user_id===userId);
        const userAbsences=lastPeopleAbsenceRows.filter(row=>row.user_id===userId);
        const summary={
          user_id:userId,
          hours:userEntries.reduce((sum,row)=>sum+Number(row.hours),0),
          vacation:0,
          medical:0,
          away:0,
          dayoff:0,
          other:0,
          occurrence_types:[...new Set(userAbsences.map(row=>absenceTypeLabel(row.absence_type)))]
        };
        userAbsences.forEach(row=>summary[absenceCategory(row.absence_type)]+=Number(row.days_in_filter||0));
        summary.total_days=summary.vacation+summary.medical+summary.away+summary.dayoff+summary.other;
        return summary;
      }).sort((a,b)=>profileName(a.user_id).localeCompare(profileName(b.user_id),"pt-BR"));

      const totalHours=lastPeopleReportRows.reduce((sum,row)=>sum+row.hours,0);
      const vacationDays=lastPeopleReportRows.reduce((sum,row)=>sum+row.vacation,0);
      const awayDays=lastPeopleReportRows.reduce((sum,row)=>sum+row.medical+row.away+row.dayoff+row.other,0);
      const usersWithAbsence=lastPeopleReportRows.filter(row=>row.total_days>0).length;

      $("peopleReportHours").textContent=fmt(totalHours);
      $("peopleReportVacationDays").textContent=vacationDays;
      $("peopleReportAwayDays").textContent=awayDays;
      $("peopleReportUsersWithAbsence").textContent=usersWithAbsence;

      $("peopleReportTable").innerHTML=lastPeopleReportRows.map(row=>`<tr>
        <td>${esc(profileName(row.user_id))}</td>
        <td>${fmt(row.hours)}</td>
        <td>${row.vacation}</td>
        <td>${row.medical}</td>
        <td>${row.away}</td>
        <td>${row.dayoff}</td>
        <td>${row.other}</td>
        <td><strong>${row.total_days}</strong></td>
        <td>${esc(row.occurrence_types.join(", ")||"Sem ausência no período")}</td>
      </tr>`).join("")||'<tr><td colspan="9" class="empty">Sem dados no período</td></tr>';

      $("peopleAbsenceReportTable").innerHTML=lastPeopleAbsenceRows.map(row=>{
        const status=absenceStatus(row);
        return `<tr>
          <td>${esc(profileName(row.user_id))}</td>
          <td>${esc(absenceTypeLabel(row.absence_type))}</td>
          <td>${dateBR(row.start_date)}</td>
          <td>${dateBR(row.end_date)}</td>
          <td>${row.days_in_filter}</td>
          <td><span class="badge absence-${status}">${absenceStatusLabel(status)}</span></td>
          <td><span class="badge approval-${absenceApprovalStatus(row)}">${absenceApprovalLabel(absenceApprovalStatus(row))}</span></td>
          <td>${esc(row.notes||"—")}</td>
        </tr>`;
      }).join("")||'<tr><td colspan="8" class="empty">Nenhuma férias ou afastamento no período</td></tr>';
    }catch(e){handleError(e,"Não foi possível gerar o relatório de férias e afastamentos.")}
  }

  async function renderActiveReport(){
    const active=document.querySelector("[data-report-view].active")?.dataset.reportView||"projects";
    if(active==="people") await renderPeopleReport();
    else await renderReport();
  }

  function switchReportView(view){
    document.querySelectorAll("[data-report-view]").forEach(button=>button.classList.toggle("active",button.dataset.reportView===view));
    $("projectReportPanel").hidden=view!=="projects";
    $("peopleReportPanel").hidden=view!=="people";
    if(view==="people") renderPeopleReport();
    else renderReport();
  }

  document.querySelectorAll("[data-report-view]").forEach(button=>{
    button.addEventListener("click",()=>switchReportView(button.dataset.reportView));
  });

  $("generateReportBtn").onclick=renderReport;
  $("generatePeopleReportBtn").onclick=renderPeopleReport;

  $("exportReportBtn").onclick=()=>{
    const lines=[["Data","Colaborador","Projeto","Atividade","Horas","Detalhamento","Status"],...lastReportRows.map(x=>[x.entry_date,profileName(x.user_id),projectName(x.project_id),activityName(x.activity_id),String(x.hours).replace(".",","),x.details,statusLabel(x.status)])];
    downloadCsv(`apontamentos_${today()}.csv`,lines);
  };

  $("exportPeopleReportBtn").onclick=()=>{
    const lines=[["Colaborador","Horas apontadas","Dias de férias","Dias de atestado","Dias de afastamentos/licenças","Dias de folga","Outros dias","Total de dias de ausência","Ocorrências no período"],...lastPeopleReportRows.map(row=>[
      profileName(row.user_id),String(row.hours).replace(".",","),row.vacation,row.medical,row.away,row.dayoff,row.other,row.total_days,row.occurrence_types.join(", ")||"Sem ausência no período"
    ])];
    downloadCsv(`resumo_equipe_horas_ausencias_${today()}.csv`,lines);
  };

  $("exportPeopleAbsencesBtn").onclick=()=>{
    const lines=[["Colaborador","Tipo","Data inicial","Data final","Dias no período filtrado","Situação","Aprovação","Observação"],...lastPeopleAbsenceRows.map(row=>[
      profileName(row.user_id),absenceTypeLabel(row.absence_type),row.start_date,row.end_date,row.days_in_filter,absenceStatusLabel(absenceStatus(row)),absenceApprovalLabel(absenceApprovalStatus(row)),row.notes||""
    ])];
    downloadCsv(`detalhes_ferias_afastamentos_${today()}.csv`,lines);
  };

  $("projectForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("projects").insert({name:$("projectName").value.trim(),description:$("projectDescription").value.trim(),created_by:me.id});if(error)handleError(error);else{$("projectForm").reset();toast("Projeto adicionado.");await reloadCatalogs()}};
  $("activityForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("activities").insert({name:$("activityName").value.trim(),activity_type:$("activityType").value,frequency:$("activityFrequency").value.trim(),responsible_name:$("activityResponsible").value.trim(),backup_name:$("activityBackup").value.trim(),created_by:me.id});if(error)handleError(error);else{$("activityForm").reset();toast("Atividade adicionada.");await reloadCatalogs()}};
  $("holidayForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("holidays").insert({holiday_date:$("holidayDate").value,name:$("holidayName").value.trim()});if(error)handleError(error);else{$("holidayForm").reset();toast("Feriado adicionado.");await reloadCatalogs()}};

  async function reloadCatalogs(){await loadBaseData();await renderCatalogs()}

  function renderProfile() {
    $("profileName").value = me?.full_name || "";
    $("profileEmail").value = me?.email || session?.user?.email || "";
    $("profileDailyHours").value = me?.daily_hours || 8;
    $("profileRole").value = roleLabel(me?.role);
  }

  $("profileForm").onsubmit = async (e) => {
    e.preventDefault();
    showLoading(true);
    try {
      const {error} = await sb.rpc("update_my_profile", {
        p_full_name: $("profileName").value.trim(),
        p_daily_hours: Number($("profileDailyHours").value)
      });
      if (error) throw error;
      await loadBaseData();
      renderProfile();
      toast("Perfil atualizado.");
    } catch (error) {
      handleError(error, "Não foi possível atualizar o perfil. Execute o arquivo ATUALIZAR_BANCO_v2.1.sql no Supabase.");
    } finally {
      showLoading(false);
    }
  };

  async function renderCatalogs(){
    $("projectsTable").innerHTML=projects.map(x=>`<tr><td>${esc(x.name)}</td><td><span class="badge">${x.active?"Ativo":"Inativo"}</span></td><td><div class="table-actions"><button class="btn primary small" data-edit-project="${x.id}">Editar</button><button class="btn secondary small" data-toggle-project="${x.id}" data-active="${x.active}">${x.active?"Inativar":"Ativar"}</button><button class="btn danger small" data-delete-project="${x.id}">Excluir</button></div></td></tr>`).join("");
    $("activitiesTable").innerHTML=activities.map(x=>`<tr><td>${esc(x.name)}</td><td>${esc(x.activity_type)}</td><td>${esc(x.responsible_name||"—")}</td><td>${esc(x.backup_name||"—")}</td><td><span class="badge">${x.active?"Ativa":"Inativa"}</span></td><td><div class="table-actions"><button class="btn primary small" data-edit-activity="${x.id}">Editar</button><button class="btn secondary small" data-toggle-activity="${x.id}" data-active="${x.active}">${x.active?"Inativar":"Ativar"}</button><button class="btn danger small" data-delete-activity="${x.id}">Excluir</button></div></td></tr>`).join("");
    $("holidaysTable").innerHTML=holidays.map(x=>`<tr><td>${dateBR(x.holiday_date)}</td><td>${esc(x.name)}</td><td><div class="table-actions"><button class="btn primary small" data-edit-holiday="${x.id}">Editar</button><button class="btn danger small" data-delete-holiday="${x.id}">Excluir</button></div></td></tr>`).join("")||'<tr><td colspan="3" class="empty">Nenhum feriado</td></tr>';
  }
  $("projectsTable").onclick=async e=>{
    const editId=e.target.dataset.editProject;
    const toggleId=e.target.dataset.toggleProject;
    const deleteId=e.target.dataset.deleteProject;
    if(editId){
      const x=projects.find(p=>p.id===editId);
      $("editProjectId").value=x.id;$("editProjectName").value=x.name;$("editProjectDescription").value=x.description||"";$("editProjectActive").value=String(x.active);
      $("editProjectDialog").showModal();
    }
    if(toggleId){const{error}=await sb.from("projects").update({active:e.target.dataset.active!=="true"}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs()}
    if(deleteId&&confirm("Excluir este projeto? Só é possível apagar projetos sem apontamentos.")){
      const{error}=await sb.rpc("aponta_delete_project_v28",{p_id:deleteId});
      if(error)handleError(error,"Projeto com histórico deve ser inativado.");else{toast("Projeto excluído.");reloadCatalogs()}
    }
  };
  $("saveProjectEditBtn").onclick=async e=>{
    e.preventDefault();showLoading(true);
    try{
      const{error}=await sb.from("projects").update({name:$("editProjectName").value.trim(),description:$("editProjectDescription").value.trim(),active:$("editProjectActive").value==="true"}).eq("id",$("editProjectId").value);
      if(error)throw error;$("editProjectDialog").close();toast("Projeto atualizado.");await reloadCatalogs();
    }catch(error){handleError(error)}finally{showLoading(false)}
  };

  $("activitiesTable").onclick=async e=>{
    const editId=e.target.dataset.editActivity;
    const toggleId=e.target.dataset.toggleActivity;
    const deleteId=e.target.dataset.deleteActivity;
    if(editId){
      const x=activities.find(a=>a.id===editId);
      $("editActivityId").value=x.id;$("editActivityName").value=x.name;$("editActivityType").value=x.activity_type;$("editActivityFrequency").value=x.frequency||"";$("editActivityResponsible").value=x.responsible_name||"";$("editActivityBackup").value=x.backup_name||"";$("editActivityActive").value=String(x.active);
      $("editActivityDialog").showModal();
    }
    if(toggleId){const{error}=await sb.from("activities").update({active:e.target.dataset.active!=="true"}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs()}
    if(deleteId&&confirm("Excluir esta atividade? Só é possível apagar atividades sem apontamentos.")){
      const{error}=await sb.rpc("aponta_delete_activity_v28",{p_id:deleteId});
      if(error)handleError(error,"Atividade com histórico deve ser inativada.");else{toast("Atividade excluída.");reloadCatalogs()}
    }
  };
  $("saveActivityEditBtn").onclick=async e=>{
    e.preventDefault();showLoading(true);
    try{
      const{error}=await sb.from("activities").update({name:$("editActivityName").value.trim(),activity_type:$("editActivityType").value,frequency:$("editActivityFrequency").value.trim(),responsible_name:$("editActivityResponsible").value.trim(),backup_name:$("editActivityBackup").value.trim(),active:$("editActivityActive").value==="true"}).eq("id",$("editActivityId").value);
      if(error)throw error;$("editActivityDialog").close();toast("Atividade atualizada.");await reloadCatalogs();
    }catch(error){handleError(error)}finally{showLoading(false)}
  };

  $("holidaysTable").onclick=async e=>{
    const editId=e.target.dataset.editHoliday;
    const deleteId=e.target.dataset.deleteHoliday;
    if(editId){
      const x=holidays.find(h=>h.id===editId);
      $("editHolidayId").value=x.id;$("editHolidayDate").value=x.holiday_date;$("editHolidayName").value=x.name;
      $("editHolidayDialog").showModal();
    }
    if(deleteId&&confirm("Excluir este feriado?")){const{error}=await sb.from("holidays").delete().eq("id",deleteId);if(error)handleError(error);else reloadCatalogs()}
  };
  $("saveHolidayEditBtn").onclick=async e=>{
    e.preventDefault();showLoading(true);
    try{
      const{error}=await sb.from("holidays").update({holiday_date:$("editHolidayDate").value,name:$("editHolidayName").value.trim()}).eq("id",$("editHolidayId").value);
      if(error)throw error;$("editHolidayDialog").close();toast("Feriado atualizado.");await reloadCatalogs();
    }catch(error){handleError(error)}finally{showLoading(false)}
  };


  let excelImportAnalysis = null;

  function normalizeImportText(value) {
    return String(value ?? "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .trim()
      .replace(/\s+/g, " ")
      .toUpperCase();
  }

  function parseExcelDate(value) {
    if (!value) return null;

    if (value instanceof Date && !Number.isNaN(value.getTime())) {
      const year = value.getFullYear();
      const month = String(value.getMonth() + 1).padStart(2, "0");
      const day = String(value.getDate()).padStart(2, "0");
      return `${year}-${month}-${day}`;
    }

    if (typeof value === "number") {
      const parsed = XLSX.SSF.parse_date_code(value);
      if (!parsed) return null;
      return `${String(parsed.y).padStart(4, "0")}-${String(parsed.m).padStart(2, "0")}-${String(parsed.d).padStart(2, "0")}`;
    }

    const text = String(value).trim();
    let match = text.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$/);
    if (match) {
      return `${match[3]}-${match[2].padStart(2, "0")}-${match[1].padStart(2, "0")}`;
    }

    match = text.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    return match ? text : null;
  }

  function toImportNumber(value) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value !== "string") return null;
    const cleaned = value.trim().replace(/\s/g, "").replace(",", ".");
    if (!cleaned || !/^-?\d+(\.\d+)?$/.test(cleaned)) return null;
    const number = Number(cleaned);
    return Number.isFinite(number) ? number : null;
  }

  function profileMatchScore(sheetName, profileName) {
    const sheet = normalizeImportText(sheetName);
    const profile = normalizeImportText(profileName);
    if (!sheet || !profile) return 0;
    if (sheet === profile) return 100;

    const sheetTokens = sheet.split(" ").filter(Boolean);
    const profileTokens = profile.split(" ").filter(Boolean);

    if (
      sheetTokens.length >= 2 &&
      profileTokens.length >= 2 &&
      sheetTokens[0] === profileTokens[0] &&
      sheetTokens[sheetTokens.length - 1] === profileTokens[profileTokens.length - 1]
    ) return 95;

    if (sheetTokens.every(token => profileTokens.includes(token))) return 85;
    if (profileTokens.every(token => sheetTokens.includes(token))) return 80;
    if (profile.includes(sheet) || sheet.includes(profile)) return 70;
    return 0;
  }

  function findBestProfileForSheet(sheetName) {
    let best = null;
    let bestScore = 0;
    let tied = false;

    profiles.filter(profile => profile.active).forEach(profile => {
      const score = profileMatchScore(sheetName, profile.full_name);
      if (score > bestScore) {
        best = profile;
        bestScore = score;
        tied = false;
      } else if (score > 0 && score === bestScore) {
        tied = true;
      }
    });

    return bestScore >= 80 && !tied ? best : null;
  }

  function groupConsecutiveDates(dates) {
    const sorted = [...new Set(dates)].sort();
    const groups = [];

    sorted.forEach(date => {
      const last = groups[groups.length - 1];
      if (!last) {
        groups.push({start: date, end: date});
        return;
      }

      const expected = new Date(`${last.end}T12:00:00Z`);
      expected.setUTCDate(expected.getUTCDate() + 1);
      const expectedIso = expected.toISOString().slice(0, 10);

      if (date === expectedIso) last.end = date;
      else groups.push({start: date, end: date});
    });

    return groups;
  }

  function setImportProgress(percent, text) {
    const container = $("importProgress");
    container.hidden = false;
    $("importProgressBar").style.width = `${Math.max(0, Math.min(100, percent))}%`;
    $("importProgressText").textContent = text;
  }

  function renderExcelImportPage() {
    if (!isAdmin()) return;
    if (!excelImportAnalysis) {
      $("executeExcelImportBtn").disabled = true;
    }
  }

  async function analyzeExcelWorkbook(file) {
    if (!window.XLSX) {
      throw new Error("A biblioteca de leitura do Excel não foi carregada. Atualize a página e tente novamente.");
    }

    const arrayBuffer = await file.arrayBuffer();
    const workbook = XLSX.read(arrayBuffer, {
      type: "array",
      cellDates: true,
      cellNF: false,
      cellText: false
    });

    const activityDefinitions = new Map();
    const activitiesSheetName = workbook.SheetNames.find(
      name => normalizeImportText(name) === "ATIVIDADES"
    );

    if (activitiesSheetName) {
      const rows = XLSX.utils.sheet_to_json(workbook.Sheets[activitiesSheetName], {
        header: 1,
        raw: true,
        defval: null
      });

      rows.slice(1).forEach(row => {
        const activityName = String(row[1] ?? "").trim();
        if (!activityName) return;

        activityDefinitions.set(normalizeImportText(activityName), {
          name: activityName,
          activity_type: String(row[0] ?? "Demanda").trim() || "Demanda",
          frequency: String(row[2] ?? "").trim(),
          responsible_name: String(row[3] ?? "").trim(),
          backup_name: String(row[4] ?? "").trim()
        });
      });
    }

    const ignoredSheets = new Set(["TOTAL", "ATIVIDADES"]);
    const projectMap = new Map();
    const activityMap = new Map(activityDefinitions);
    const holidayDates = new Set();
    const employeeSheets = [];

    workbook.SheetNames.forEach(sheetName => {
      if (ignoredSheets.has(normalizeImportText(sheetName))) return;

      const rows = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], {
        header: 1,
        raw: true,
        defval: null
      });

      if (rows.length < 4) return;

      const dateHeader = rows[2] || [];
      const columns = [];
      for (let column = 3; column < dateHeader.length; column += 1) {
        const isoDate = parseExcelDate(dateHeader[column]);
        if (isoDate) columns.push({column, date: isoDate});
      }

      if (!columns.length) return;

      const entries = [];
      const vacationDates = new Set();
      let ignoredFuture = 0;
      let ignoredInvalid = 0;
      let totalHours = 0;

      for (let rowIndex = 3; rowIndex < rows.length; rowIndex += 1) {
        const row = rows[rowIndex] || [];
        const projectName = String(row[0] ?? "").trim();
        const activityName = String(row[1] ?? "").trim();
        const detailRequired = normalizeImportText(row[2]) === "X";

        if (!projectName || !activityName || activityName === "-") continue;

        const projectKey = normalizeImportText(projectName);
        const activityKey = normalizeImportText(activityName);

        if (!projectMap.has(projectKey)) {
          projectMap.set(projectKey, {name: projectName, description: "Importado da planilha Apontamento_P3.xlsx"});
        }

        if (!activityMap.has(activityKey)) {
          activityMap.set(activityKey, {
            name: activityName,
            activity_type: "Demanda",
            frequency: "",
            responsible_name: "",
            backup_name: ""
          });
        }

        columns.forEach(({column, date}) => {
          const value = row[column];
          if (value === null || value === undefined || value === "") return;

          const numericValue = toImportNumber(value);

          if (numericValue !== null) {
            if (numericValue <= 0) return;
            if (date > today()) {
              ignoredFuture += 1;
              return;
            }

            entries.push({
              date,
              projectKey,
              activityKey,
              hours: numericValue,
              details:
                `Importado da planilha ${file.name}` +
                (detailRequired ? " — atividade marcada para detalhamento na planilha original." : "")
            });
            totalHours += numericValue;
            return;
          }

          const special = normalizeImportText(value);
          if (!special) return;

          if (special.includes("FERIADO") || special === "FER") {
            holidayDates.add(date);
          } else if (special.includes("FERIAS")) {
            vacationDates.add(date);
          } else if (!["FDS", "S", "D", "SAB", "DOM"].includes(special)) {
            ignoredInvalid += 1;
          }
        });
      }

      const dates = columns.map(item => item.date).sort();
      employeeSheets.push({
        sheetName,
        matchedProfile: findBestProfileForSheet(sheetName),
        entries,
        vacationDates: [...vacationDates],
        startDate: dates[0],
        endDate: dates[dates.length - 1],
        totalHours,
        ignoredFuture,
        ignoredInvalid
      });
    });

    return {
      fileName: file.name,
      hasActivitiesSheet: Boolean(activitiesSheetName),
      employeeSheets,
      projects: [...projectMap.values()],
      activities: [...activityMap.values()],
      holidays: [...holidayDates].sort()
    };
  }

  function renderExcelAnalysis() {
    const analysis = excelImportAnalysis;
    if (!analysis) return;

    const validEntries = analysis.employeeSheets.reduce((sum, sheet) => sum + sheet.entries.length, 0);
    const unmatched = analysis.employeeSheets.filter(sheet => !sheet.matchedProfile);
    const futureCount = analysis.employeeSheets.reduce((sum, sheet) => sum + sheet.ignoredFuture, 0);

    $("importFileName").textContent = analysis.fileName;
    $("importMetricSheets").textContent = analysis.employeeSheets.length;
    $("importMetricEntries").textContent = validEntries;
    $("importMetricProjects").textContent = analysis.projects.length;
    $("importMetricActivities").textContent = analysis.activities.length;

    const userOptions = profiles
      .filter(profile => profile.active)
      .map(profile => `<option value="${profile.id}">${esc(profile.full_name)} — ${esc(profile.email)}</option>`)
      .join("");

    $("importMappingTable").innerHTML = analysis.employeeSheets.map((sheet, index) => {
      const selectedId = sheet.matchedProfile?.id || "";
      const ignored = sheet.ignoredFuture + sheet.ignoredInvalid;
      return `<tr>
        <td><strong>${esc(sheet.sheetName)}</strong></td>
        <td>
          <select class="import-user-map" data-import-sheet="${index}">
            <option value="">Não importar esta aba</option>
            ${userOptions}
          </select>
        </td>
        <td>${dateBR(sheet.startDate)} a ${dateBR(sheet.endDate)}</td>
        <td>${fmt(sheet.totalHours)}</td>
        <td>${sheet.entries.length}</td>
        <td>${ignored}</td>
      </tr>`;
    }).join("") || '<tr><td colspan="6" class="empty">Nenhuma aba de colaborador reconhecida.</td></tr>';

    document.querySelectorAll(".import-user-map").forEach(select => {
      const sheet = analysis.employeeSheets[Number(select.dataset.importSheet)];
      select.value = sheet.matchedProfile?.id || "";
    });

    const messages = [];
    if (unmatched.length) {
      messages.push(
        `${unmatched.length} aba(s) não foram relacionadas automaticamente: ` +
        unmatched.map(sheet => sheet.sheetName).join(", ") +
        ". Selecione os usuários manualmente."
      );
    }
    if (futureCount) {
      messages.push(`${futureCount} apontamento(s) em datas futuras serão ignorados.`);
    }
    if (!analysis.hasActivitiesSheet) {
      messages.push("A aba Atividades não foi encontrada; as atividades serão criadas apenas com os nomes das abas dos colaboradores.");
    }

    $("importWarnings").hidden = messages.length === 0;
    $("importWarnings").innerHTML = messages.map(message => `<p>${esc(message)}</p>`).join("");
    $("executeExcelImportBtn").disabled = analysis.employeeSheets.length === 0;
    $("importResult").hidden = true;
  }

  $("analyzeExcelBtn").onclick = async () => {
    const file = $("importExcelFile").files[0];
    if (!file) {
      toast("Selecione a planilha Apontamento_P3.xlsx.", true);
      return;
    }

    showLoading(true);
    try {
      excelImportAnalysis = await analyzeExcelWorkbook(file);
      renderExcelAnalysis();
      toast("Planilha analisada. Confira o relacionamento dos colaboradores.");
    } catch (error) {
      excelImportAnalysis = null;
      $("executeExcelImportBtn").disabled = true;
      handleError(error, "Não foi possível analisar a planilha.");
    } finally {
      showLoading(false);
    }
  };

  async function insertInChunks(table, rows, chunkSize = 200) {
    let inserted = 0;
    for (let index = 0; index < rows.length; index += chunkSize) {
      const chunk = rows.slice(index, index + chunkSize);
      const {error} = await sb.from(table).insert(chunk);
      if (error) throw error;
      inserted += chunk.length;
    }
    return inserted;
  }

  $("executeExcelImportBtn").onclick = async () => {
    if (!isAdmin() || !excelImportAnalysis) return;

    const mappings = new Map();
    document.querySelectorAll(".import-user-map").forEach(select => {
      if (select.value) mappings.set(Number(select.dataset.importSheet), select.value);
    });

    if ($("importEntries").checked && mappings.size === 0) {
      toast("Relacione pelo menos uma aba a um usuário.", true);
      return;
    }

    const confirmed = window.confirm(
      "IMPORTAR BANCO DE DADOS\n\n" +
      "A importação adicionará dados ao Supabase e pulará apontamentos já existentes.\n" +
      "As abas sem usuário selecionado não serão importadas.\n\n" +
      "Deseja continuar?"
    );
    if (!confirmed) return;

    $("executeExcelImportBtn").disabled = true;
    $("importResult").hidden = true;
    setImportProgress(5, "Preparando importação...");

    try {
      let projectsCreated = 0;
      let activitiesCreated = 0;
      let entriesCreated = 0;
      let entriesSkipped = 0;
      let holidaysCreated = 0;
      let absencesCreated = 0;

      const analysis = excelImportAnalysis;

      if ($("importCatalogs").checked || $("importEntries").checked) {
        setImportProgress(15, "Importando projetos...");

        const existingProjects = new Map(projects.map(project => [normalizeImportText(project.name), project]));
        const newProjects = analysis.projects
          .filter(project => !existingProjects.has(normalizeImportText(project.name)))
          .map(project => ({
            name: project.name,
            description: project.description,
            active: true,
            created_by: me.id
          }));

        if (newProjects.length) {
          projectsCreated = await insertInChunks("projects", newProjects);
        }

        setImportProgress(25, "Importando atividades...");

        const existingActivities = new Map(activities.map(activity => [normalizeImportText(activity.name), activity]));
        const newActivities = analysis.activities
          .filter(activity => !existingActivities.has(normalizeImportText(activity.name)))
          .map(activity => ({
            name: activity.name,
            activity_type: activity.activity_type || "Demanda",
            frequency: activity.frequency || "",
            responsible_name: activity.responsible_name || "",
            backup_name: activity.backup_name || "",
            active: true,
            created_by: me.id
          }));

        const activitiesToUpdate = analysis.activities
          .map(activity => {
            const existing = existingActivities.get(normalizeImportText(activity.name));
            if (!existing) return null;
            return {
              id: existing.id,
              name: existing.name,
              activity_type: activity.activity_type || existing.activity_type || "Demanda",
              frequency: activity.frequency || existing.frequency || "",
              responsible_name: activity.responsible_name || existing.responsible_name || "",
              backup_name: activity.backup_name || existing.backup_name || "",
              active: existing.active,
              created_by: existing.created_by || me.id
            };
          })
          .filter(Boolean);

        if (newActivities.length) {
          activitiesCreated = await insertInChunks("activities", newActivities);
        }

        if (activitiesToUpdate.length) {
          const {error: updateActivitiesError} = await sb
            .from("activities")
            .upsert(activitiesToUpdate, {onConflict: "id"});
          if (updateActivitiesError) throw updateActivitiesError;
        }

        await loadBaseData();
      }

      if ($("importHolidays").checked && analysis.holidays.length) {
        setImportProgress(35, "Importando feriados...");

        const existingHolidayDates = new Set(holidays.map(holiday => holiday.holiday_date));
        const newHolidays = analysis.holidays
          .filter(date => !existingHolidayDates.has(date))
          .map(date => ({holiday_date: date, name: "Feriado — importado da planilha"}));

        if (newHolidays.length) {
          holidaysCreated = await insertInChunks("holidays", newHolidays);
        }
      }

      if ($("importVacations").checked) {
        setImportProgress(45, "Importando férias...");

        const absenceRows = [];
        for (const [sheetIndex, userId] of mappings.entries()) {
          const sheet = analysis.employeeSheets[sheetIndex];
          groupConsecutiveDates(sheet.vacationDates).forEach(period => {
            absenceRows.push({
              user_id: userId,
              start_date: period.start,
              end_date: period.end,
              absence_type: "Férias",
              notes: `Importado da aba ${sheet.sheetName} — ${analysis.fileName}`,
              approval_status: "aprovado",
              approved_by: me.id,
              approved_at: new Date().toISOString()
            });
          });
        }

        for (const row of absenceRows) {
          const {data, error} = await sb
            .from("absences")
            .select("id")
            .eq("user_id", row.user_id)
            .eq("start_date", row.start_date)
            .eq("end_date", row.end_date)
            .eq("absence_type", "Férias")
            .maybeSingle();

          if (error) throw error;
          if (data) continue;

          const {error: insertError} = await sb.from("absences").insert(row);
          if (insertError) throw insertError;
          absencesCreated += 1;
        }
      }

      if ($("importEntries").checked) {
        setImportProgress(55, "Preparando apontamentos...");

        const projectByKey = new Map(projects.map(project => [normalizeImportText(project.name), project]));
        const activityByKey = new Map(activities.map(activity => [normalizeImportText(activity.name), activity]));
        const rowsToInsert = [];

        for (const [sheetIndex, userId] of mappings.entries()) {
          const sheet = analysis.employeeSheets[sheetIndex];
          if (!sheet.entries.length) continue;

          const start = sheet.entries.reduce((min, entry) => entry.date < min ? entry.date : min, sheet.entries[0].date);
          const end = sheet.entries.reduce((max, entry) => entry.date > max ? entry.date : max, sheet.entries[0].date);

          const {data: existingRows, error} = await sb
            .from("time_entries")
            .select("entry_date,project_id,activity_id")
            .eq("user_id", userId)
            .gte("entry_date", start)
            .lte("entry_date", end);

          if (error) throw error;

          const existingKeys = new Set(
            (existingRows || []).map(row => `${row.entry_date}|${row.project_id}|${row.activity_id}`)
          );

          sheet.entries.forEach(entry => {
            const project = projectByKey.get(entry.projectKey);
            const activity = activityByKey.get(entry.activityKey);

            if (!project || !activity) {
              entriesSkipped += 1;
              return;
            }

            const duplicateKey = `${entry.date}|${project.id}|${activity.id}`;
            if (existingKeys.has(duplicateKey)) {
              entriesSkipped += 1;
              return;
            }

            existingKeys.add(duplicateKey);
            rowsToInsert.push({
              user_id: userId,
              entry_date: entry.date,
              project_id: project.id,
              activity_id: activity.id,
              hours: entry.hours,
              details: entry.details,
              status: "rascunho"
            });
          });
        }

        setImportProgress(70, `Importando ${rowsToInsert.length} apontamento(s)...`);

        const chunkSize = 150;
        for (let index = 0; index < rowsToInsert.length; index += chunkSize) {
          const chunk = rowsToInsert.slice(index, index + chunkSize);
          const {error} = await sb.from("time_entries").insert(chunk);
          if (error) throw error;
          entriesCreated += chunk.length;

          const fraction = rowsToInsert.length
            ? (index + chunk.length) / rowsToInsert.length
            : 1;
          setImportProgress(70 + Math.round(fraction * 25), `Importando apontamentos: ${entriesCreated}/${rowsToInsert.length}`);
        }
      }

      await loadBaseData();
      await Promise.all([renderDashboard(), renderEntries(), renderAbsences(), renderCatalogs(), renderReport(), renderPeopleReport()]);

      setImportProgress(100, "Importação concluída.");
      $("importResult").hidden = false;
      $("importResult").innerHTML = `
        <h3>Importação concluída</h3>
        <div class="import-result-grid">
          <span><strong>${projectsCreated}</strong> projetos criados</span>
          <span><strong>${activitiesCreated}</strong> atividades criadas</span>
          <span><strong>${entriesCreated}</strong> apontamentos importados</span>
          <span><strong>${entriesSkipped}</strong> apontamentos já existentes ou ignorados</span>
          <span><strong>${holidaysCreated}</strong> feriados criados</span>
          <span><strong>${absencesCreated}</strong> períodos de férias criados</span>
        </div>
      `;

      toast("Banco de dados importado com sucesso.");
    } catch (error) {
      setImportProgress(100, "A importação foi interrompida.");
      $("importResult").hidden = false;
      $("importResult").classList.add("error");
      $("importResult").textContent =
        "Não foi possível concluir a importação. Confira se o SQL da versão 2.6 foi executado e tente novamente.";
      handleError(error);
    } finally {
      $("executeExcelImportBtn").disabled = false;
    }
  };


  function renderBackupPage() {
    if (!isAdmin()) return;
    $("restoreConfirmation").value = "";
    $("restoreBackupFile").value = "";
  }

  function downloadJsonFile(fileName, data) {
    const content = JSON.stringify(data, null, 2);
    const blob = new Blob([content], {type: "application/json;charset=utf-8"});
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = fileName;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  async function invokeBackupFunction(body) {
    const {data, error} = await sb.functions.invoke("backup-aponta-p3", {body});
    if (error) {
      let message = error.message || "Falha ao acessar a função de backup.";
      try {
        const context = error.context;
        if (context && typeof context.json === "function") {
          const details = await context.json();
          if (details?.error) message = details.error;
        }
      } catch (_) {}
      throw new Error(message);
    }
    if (data?.error) throw new Error(data.error);
    return data;
  }

  $("downloadBackupBtn").onclick = async () => {
    if (!isAdmin()) return;

    showLoading(true);
    $("manualBackupStatus").textContent = "Gerando backup...";

    try {
      const result = await invokeBackupFunction({action: "export"});
      if (!result?.backup) throw new Error("A função não retornou o arquivo de backup.");

      const stamp = new Date().toISOString()
        .replace(/:/g, "-")
        .replace(/\.\d{3}Z$/, "")
        .replace("T", "_");

      const fileName = `Aponta_P3_Backup_${stamp}.json`;
      downloadJsonFile(fileName, result.backup);

      $("manualBackupStatus").textContent =
        `Backup gerado com sucesso: ${fileName} · ${result.recordCount || 0} registros.`;
      toast("Backup baixado com sucesso.");
    } catch (error) {
      $("manualBackupStatus").textContent =
        "Não foi possível gerar o backup. Confira a Edge Function backup-aponta-p3.";
      handleError(error);
    } finally {
      showLoading(false);
    }
  };

  $("restoreBackupBtn").onclick = async () => {
    if (!isAdmin()) return;

    const file = $("restoreBackupFile").files[0];
    if (!file) {
      toast("Selecione um arquivo JSON de backup.", true);
      return;
    }

    if ($("restoreConfirmation").value.trim().toUpperCase() !== "RESTAURAR") {
      toast("Digite RESTAURAR para confirmar.", true);
      $("restoreConfirmation").focus();
      return;
    }

    const confirmed = window.confirm(
      "RESTAURAR BACKUP\n\n" +
      "Os registros do arquivo serão mesclados com os dados atuais.\n" +
      "Essa operação pode substituir alterações feitas nos mesmos registros.\n\n" +
      "Deseja continuar?"
    );
    if (!confirmed) return;

    showLoading(true);

    try {
      const text = await file.text();
      let backup;
      try {
        backup = JSON.parse(text);
      } catch (_) {
        throw new Error("O arquivo selecionado não contém um JSON válido.");
      }

      if (!backup?.format || !backup?.tables) {
        throw new Error("Este arquivo não foi reconhecido como backup do Aponta P3.");
      }

      const result = await invokeBackupFunction({
        action: "restore",
        backup,
        mode: "merge"
      });

      await loadBaseData();
      await Promise.all([
        renderDashboard(),
        renderEntries(),
        renderAbsences(),
        renderCatalogs(),
        renderTeam(),
        loadClosing(),
        renderReport(),
        renderPeopleReport()
      ]);

      $("restoreConfirmation").value = "";
      $("restoreBackupFile").value = "";

      const restored = Number(result?.restoredRecords || 0);
      const skipped = Number(result?.skippedRecords || 0);
      toast(`Restauração concluída: ${restored} registros processados e ${skipped} ignorados.`);
    } catch (error) {
      handleError(error, "Não foi possível restaurar o backup.");
    } finally {
      showLoading(false);
    }
  };

  function pendingRegistrationProfiles(){
    if(!isManager())return [];

    return profiles
      .filter(profile => {
        if(registrationStatus(profile)!=="pendente")return false;
        if(isAdmin())return true;
        return profile.role==="colaborador";
      })
      .sort((a,b)=>String(a.full_name||"").localeCompare(
        String(b.full_name||""),
        "pt-BR",
        {sensitivity:"base"}
      ));
  }

  function renderPendingRegistrations(){
    if(!isManager())return;

    const list=$("pendingRegistrationsList");
    const count=$("pendingRegistrationsCount");
    const warning=$("registrationFeatureWarning");
    if(!list||!count)return;

    if(!registrationFeatureInstalled()){
      count.textContent="Configuração pendente";
      warning.hidden=false;
      warning.innerHTML=
        "<strong>A aprovação de inscrições ainda não está instalada no banco.</strong>"+
        "<span> Execute o arquivo ATUALIZAR_BANCO_v2.11_APROVACAO_USUARIOS.sql no SQL Editor do Supabase.</span>";
      list.innerHTML="";
      return;
    }

    warning.hidden=true;
    warning.textContent="";

    const pending=pendingRegistrationProfiles();
    count.textContent=`${pending.length} ${pending.length===1?"pendente":"pendentes"}`;

    if(!pending.length){
      list.innerHTML=`
        <div class="pending-registrations-empty">
          <strong>Nenhuma inscrição aguardando aprovação.</strong>
          <span>Novos cadastros aparecerão aqui automaticamente.</span>
        </div>`;
      return;
    }

    list.innerHTML=pending.map(person=>`
      <article class="pending-registration-item">
        <div class="pending-registration-person">
          <strong>${esc(person.full_name)}</strong>
          <span>${esc(person.email)}</span>
          <small>${esc(roleLabel(person.role))}</small>
        </div>
        <div class="pending-registration-status">
          <span class="badge registration-pendente">Pendente</span>
        </div>
        <div class="pending-registration-actions">
          <button
            class="btn success mobile-approval-button"
            type="button"
            data-approve-registration="${person.id}">
            Aprovar integrante
          </button>
          <button
            class="btn danger mobile-reject-button"
            type="button"
            data-reject-registration="${person.id}">
            Rejeitar
          </button>
        </div>
      </article>
    `).join("");
  }

  async function renderTeam(){
    if(!isManager())return;

    renderPendingRegistrations();

    const registrationOrder={pendente:0,rejeitado:1,aprovado:2};
    const orderedProfiles=[...profiles].sort((a,b)=>{
      const statusDiff=(registrationOrder[registrationStatus(a)]??9)-
        (registrationOrder[registrationStatus(b)]??9);
      if(statusDiff!==0)return statusDiff;
      return String(a.full_name||"").localeCompare(
        String(b.full_name||""),
        "pt-BR",
        {sensitivity:"base"}
      );
    });

    $("teamTable").innerHTML=orderedProfiles.map(x=>{
      const status=registrationStatus(x);
      const reviewedBy=x.registration_reviewed_by?profileName(x.registration_reviewed_by):"—";
      const reviewedAt=x.registration_reviewed_at
        ?new Date(x.registration_reviewed_at).toLocaleString("pt-BR")
        :"—";

      const profileField=isAdmin()
        ?`<select data-role="${x.id}">
            <option value="colaborador" ${x.role==="colaborador"?"selected":""}>Colaborador</option>
            <option value="gestor" ${x.role==="gestor"?"selected":""}>Gestor</option>
            <option value="administrador" ${x.role==="administrador"?"selected":""}>Administrador</option>
          </select>`
        :esc(roleLabel(x.role));

      const hoursField=isAdmin()
        ?`<input data-hours="${x.id}" type="number" min="1" max="24" step="0.5" value="${x.daily_hours}">`
        :fmt(x.daily_hours);

      const activeField=isAdmin()
        ?`<select data-active="${x.id}">
            <option value="true" ${x.active?"selected":""}>Sim</option>
            <option value="false" ${!x.active?"selected":""}>Não</option>
          </select>`
        :(x.active?"Sim":"Não");

      const nameField=isAdmin()
        ?`<input data-name="${x.id}" value="${esc(x.full_name)}">`
        :esc(x.full_name);

      const canManagerReview=isAdmin()||x.role==="colaborador";
      const reviewActions=canManagerReview
        ?`${status!=="aprovado"
            ?`<button class="btn success small" data-approve-registration="${x.id}">Aprovar</button>`
            :""}
          ${status!=="rejeitado"&&x.id!==me.id
            ?`<button class="btn danger small" data-reject-registration="${x.id}">Rejeitar</button>`
            :""}`
        :"";

      const adminActions=isAdmin()
        ?`<button class="btn primary small" data-save-user="${x.id}">Salvar</button>
          ${x.id!==me.id?`<button class="btn danger small" data-delete-user="${x.id}">Excluir</button>`:""}`
        :"";

      return `<tr class="team-member-row registration-row-${status}" data-registration-status="${status}">
        <td data-label="Nome">${nameField}</td>
        <td data-label="E-mail">${esc(x.email)}</td>
        <td data-label="Perfil">${profileField}</td>
        <td data-label="Jornada">${hoursField}</td>
        <td data-label="Ativo">${activeField}</td>
        <td data-label="Inscrição">
          <span class="badge registration-${status}">${registrationLabel(status)}</span>
          ${x.registration_review_note
            ?`<div class="team-review-note">${esc(x.registration_review_note)}</div>`
            :""}
        </td>
        <td data-label="Revisão">
          <div>${esc(reviewedBy)}</div>
          <small>${esc(reviewedAt)}</small>
        </td>
        <td data-label="Ações" class="team-actions-cell">
          <div class="table-actions">${reviewActions}${adminActions}</div>
        </td>
      </tr>`;
    }).join("");
  }

  async function reviewUserRegistration(id, decision) {
    const person=profiles.find(x=>x.id===id);
    if(!person)return;

    const action=decision==="aprovado"?"aprovar":"rejeitar";
    if(!confirm(`${action.charAt(0).toUpperCase()+action.slice(1)} a inscrição de ${person.full_name}?`))return;

    let note="";
    if(decision==="rejeitado"){
      note=prompt("Informe o motivo da rejeição (opcional):")||"";
    }

    showLoading(true);
    try{
      const{error}=await sb.rpc("aponta_review_registration_v211",{
        p_user_id:id,
        p_decision:decision,
        p_note:note
      });
      if(error)throw error;

      toast(decision==="aprovado"
        ?"Inscrição aprovada. O usuário já pode realizar apontamentos."
        :"Inscrição rejeitada. O acesso aos apontamentos foi bloqueado.");

      await loadBaseData();
      await Promise.all([renderTeam(),renderDashboard()]);
      renderPendingRegistrations();
    }catch(error){
      handleError(error,"Não foi possível analisar a inscrição. Execute o SQL da versão 2.11.");
    }finally{
      showLoading(false);
    }
  }

  async function deleteUserRegistration(id) {
    const person = profiles.find(x => x.id === id);
    if (!person) return;
    if (!confirm(`Excluir permanentemente o cadastro de ${person.full_name}?\n\nSó será permitido se não houver apontamentos, férias, afastamentos, fechamentos ou aprovações.`)) return;
    showLoading(true);
    try {
      const {data,error} = await sb.functions.invoke("excluir-cadastro", {body:{userId:id}});
      if (error) {
        let message = error.message || "Falha ao acessar a função excluir-cadastro.";
        try {
          if (error.context && typeof error.context.json === "function") {
            const details = await error.context.json();
            if (details?.error) message = details.error;
          }
        } catch (_) {}
        throw new Error(message);
      }
      if (data?.error) throw new Error(data.error);
      toast("Cadastro do colaborador excluído.");
      await loadBaseData();
      await Promise.all([renderTeam(),renderAbsences(),renderDashboard()]);
    } catch(error) {
      handleError(error, "Não foi possível excluir. Cadastros com histórico devem ser desativados.");
    } finally { showLoading(false); }
  }

  async function handleTeamActionClick(e){
    const actionButton=e.target.closest(
      "[data-approve-registration],[data-reject-registration],[data-save-user],[data-delete-user]"
    );
    if(!actionButton)return;

    const approveId=actionButton.dataset.approveRegistration;
    const rejectId=actionButton.dataset.rejectRegistration;
    const saveId=actionButton.dataset.saveUser;
    const deleteId=actionButton.dataset.deleteUser;

    if(approveId)return reviewUserRegistration(approveId,"aprovado");
    if(rejectId)return reviewUserRegistration(rejectId,"rejeitado");
    if(deleteId)return deleteUserRegistration(deleteId);
    if(!saveId||!isAdmin())return;

    const{error}=await sb.from("profiles").update({
      full_name:document.querySelector(`[data-name="${saveId}"]`).value.trim(),
      role:document.querySelector(`[data-role="${saveId}"]`).value,
      daily_hours:Number(document.querySelector(`[data-hours="${saveId}"]`).value),
      active:document.querySelector(`[data-active="${saveId}"]`).value==="true"
    }).eq("id",saveId);

    if(error)handleError(error);
    else{
      toast("Usuário atualizado.");
      await loadBaseData();
      await renderTeam();
    }
  }

  $("teamTable").onclick=handleTeamActionClick;
  $("pendingRegistrationsList").onclick=handleTeamActionClick;

  $("refreshPendingRegistrationsBtn").onclick=async()=>{
    showLoading(true);
    try{
      await loadBaseData();
      await renderTeam();
      toast("Lista de inscrições atualizada.");
    }catch(error){
      handleError(error,"Não foi possível atualizar as inscrições.");
    }finally{
      showLoading(false);
    }
  };

  sb.auth.onAuthStateChange((event,newSession)=>{
    if(event==="SIGNED_OUT"){session=null;me=null;app.hidden=true;authScreen.hidden=false}
    if(event==="PASSWORD_RECOVERY"){
      const password=prompt("Digite a nova senha (mínimo de 6 caracteres):");
      if(password&&password.length>=6) sb.auth.updateUser({password}).then(({error})=>error?handleError(error):toast("Senha atualizada."));
    }
  });

  if("serviceWorker" in navigator && location.protocol.startsWith("http")){
    navigator.serviceWorker
      .register("sw.js?v=2.11.3", {updateViaCache:"none"})
      .then(async registration=>{
        await registration.update();
        if(registration.waiting){
          registration.waiting.postMessage({type:"SKIP_WAITING"});
        }
      })
      .catch(console.error);

    navigator.serviceWorker.addEventListener("controllerchange",()=>{
      if(sessionStorage.getItem("aponta-p3-sw-reloaded")==="1")return;
      sessionStorage.setItem("aponta-p3-sw-reloaded","1");
      window.location.reload();
    });
  }

  boot();

  // APONTA P3 v2.11.5 — convite de instalação no celular
  let deferredInstallPrompt = null;

  const isMobileDevice = () =>
    /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) ||
    window.matchMedia("(max-width: 820px)").matches;

  const isIosDevice = () =>
    /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

  const isStandaloneMode = () =>
    window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true;

  const INSTALL_DISMISS_KEY = "aponta-p3-install-dismissed-at";
  const INSTALL_DISMISS_DAYS = 7;

  function installPromptWasRecentlyDismissed() {
    const value = Number(localStorage.getItem(INSTALL_DISMISS_KEY) || 0);
    if (!value) return false;
    return Date.now() - value < INSTALL_DISMISS_DAYS * 24 * 60 * 60 * 1000;
  }

  function hideInstallAppOverlay(remember = true) {
    const overlay = document.getElementById("installAppOverlay");
    if (overlay) overlay.hidden = true;
    if (remember) {
      localStorage.setItem(INSTALL_DISMISS_KEY, String(Date.now()));
    }
  }

  function showInstallAppOverlay(mode) {
    if (!isMobileDevice() || isStandaloneMode() || installPromptWasRecentlyDismissed()) return;

    const overlay = document.getElementById("installAppOverlay");
    if (!overlay) return;

    const androidActions = document.getElementById("androidInstallActions");
    const iosInstructions = document.getElementById("iosInstallInstructions");
    const manualInstructions = document.getElementById("manualInstallInstructions");

    androidActions.hidden = mode !== "android";
    iosInstructions.hidden = mode !== "ios";
    manualInstructions.hidden = mode !== "manual";
    overlay.hidden = false;
  }

  window.addEventListener("beforeinstallprompt", event => {
    event.preventDefault();
    deferredInstallPrompt = event;

    if (document.readyState === "complete") {
      setTimeout(() => showInstallAppOverlay("android"), 450);
    }
  });

  window.addEventListener("appinstalled", () => {
    deferredInstallPrompt = null;
    localStorage.removeItem(INSTALL_DISMISS_KEY);
    hideInstallAppOverlay(false);
    try {
      toast("Aponta P3 instalado com sucesso.");
    } catch (_) {}
  });

  document.addEventListener("DOMContentLoaded", () => {
    const closeBtn = document.getElementById("closeInstallAppBtn");
    const installBtn = document.getElementById("installAppBtn");
    const laterBtn = document.getElementById("installLaterBtn");
    const iosUnderstoodBtn = document.getElementById("iosUnderstoodBtn");
    const manualUnderstoodBtn = document.getElementById("manualUnderstoodBtn");
    const overlay = document.getElementById("installAppOverlay");

    closeBtn?.addEventListener("click", () => hideInstallAppOverlay(true));
    laterBtn?.addEventListener("click", () => hideInstallAppOverlay(true));
    iosUnderstoodBtn?.addEventListener("click", () => hideInstallAppOverlay(true));
    manualUnderstoodBtn?.addEventListener("click", () => hideInstallAppOverlay(true));

    overlay?.addEventListener("click", event => {
      if (event.target === overlay) hideInstallAppOverlay(true);
    });

    installBtn?.addEventListener("click", async () => {
      if (!deferredInstallPrompt) {
        showInstallAppOverlay("manual");
        return;
      }

      deferredInstallPrompt.prompt();
      const choice = await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;

      if (choice.outcome === "accepted") {
        hideInstallAppOverlay(false);
      } else {
        hideInstallAppOverlay(true);
      }
    });

    setTimeout(() => {
      if (!isMobileDevice() || isStandaloneMode() || installPromptWasRecentlyDismissed()) return;

      if (isIosDevice()) {
        showInstallAppOverlay("ios");
      } else if (deferredInstallPrompt) {
        showInstallAppOverlay("android");
      } else {
        showInstallAppOverlay("manual");
      }
    }, 900);
  });

  window.APONTA_P3_VERSION = "2.11.6";
})();
