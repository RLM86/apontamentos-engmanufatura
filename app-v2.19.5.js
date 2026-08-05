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
  let workAreas = [];
  let manufacturingSectors = [];
  let modules = [];
  let rooms = [];
  let panelTypes = [];
  let activityAreaLinks = [];
  let projectModules = [];
  let projectRooms = [];
  let projectRoomModules = [];
  let projectRoomInstances = [];
  let projectRoomInstanceModules = [];
  let absences = [];
  let lastReportRows = [];
  let lastPeopleReportRows = [];
  let lastPeopleAbsenceRows = [];
  let currentClosing = null;
  let closingHistoryRows = [];
  const selectedClosingHistoryIds = new Set();
  let visibleReviewableClosingIds = [];
  const selectedEntryIds = new Set();
  let visibleEditableEntryIds = [];
  const selectedActivityIds = new Set();
  let visibleActivityIds = [];

  const MAX_MONOBLOCK_MODULES = 4;

  const STANDARD_PROJECT_ROOMS = [
    {key:"DH", title:"Data Hall", short:"DH", aliases:["dh","datahall"], order:1},
    {key:"SE", title:"Sala Elétrica", short:"SE", aliases:["se","salaeletrica"], order:2},
    {key:"SC", title:"Sala Catcher", short:"SC", aliases:["sc","salacatcher","catcher"], order:3},
    {key:"SM", title:"Sala de Máquinas", short:"SM", aliases:["sm","salademaquinas","salamaquinas"], order:4},
    {key:"HVAC", title:"HVAC", short:"HVAC", aliases:["hvac","salahvac"], order:5},
    {key:"MONOBLOCO", title:"Monobloco", short:"MONO", aliases:["monobloco","mono"], order:6, monoblock:true}
  ];

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
  const dateTimeBR = (value) => {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    return date.toLocaleString("pt-BR", {
      day:"2-digit", month:"2-digit", year:"numeric",
      hour:"2-digit", minute:"2-digit"
    });
  };
  const monthLabel = (value) => {
    const month = String(value || "").slice(0, 7);
    if (!/^\d{4}-\d{2}$/.test(month)) return "—";
    const date = new Date(`${month}-01T12:00:00`);
    const label = date.toLocaleDateString("pt-BR", {month:"long", year:"numeric"});
    return label.charAt(0).toUpperCase() + label.slice(1);
  };
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
  const normalizeActivityCode = (value) => {
    const code=String(value||"").trim();
    return code ? code.replace(/^EM-/i,"").toUpperCase() : "";
  };

  const normalizeObservationRequirement = (value) => {
    const normalized=normalizeText(value);
    return (
      normalized==="sim"||
      normalized==="s"||
      normalized==="obrigatoria"||
      normalized==="obrigatorio"||
      normalized.includes("obrig")
    ) ? "Obrigatória" : "Opcional";
  };
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
  const PRIMARY_APP_URL =
    "https://apontamentos-engmanufatura.modulardtc.workers.dev/";

  const SECONDARY_APP_URL =
    "https://apontamentosengmanufatura.netlify.app/";

  const APP_ALLOWED_ORIGINS = new Set([
    new URL(PRIMARY_APP_URL).origin,
    new URL(SECONDARY_APP_URL).origin
  ]);

  const appBaseUrl = () => {
    const current = new URL(window.location.href);

    if(APP_ALLOWED_ORIGINS.has(current.origin)){
      return `${current.origin}/`;
    }

    return PRIMARY_APP_URL;
  };

  const recoveryPageUrl = () => `${appBaseUrl()}redefinir-senha`;

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

  function serializeRecoveryError(value, depth = 0, seen = new WeakSet()) {
    if (value === null || value === undefined) return value;
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      return value;
    }
    if (typeof value === "function") return `[Function ${value.name || "anonymous"}]`;
    if (depth > 3) return "[Max depth]";
    if (typeof value !== "object") return String(value);

    if (seen.has(value)) return "[Circular]";
    seen.add(value);

    const output = {};
    const keys = new Set([
      ...Object.keys(value),
      ...Object.getOwnPropertyNames(value)
    ]);

    for (const key of keys) {
      if (key === "stack") continue;
      try {
        output[key] = serializeRecoveryError(value[key], depth + 1, seen);
      } catch (_) {
        output[key] = "[Unreadable]";
      }
    }

    if (!Object.keys(output).length) {
      try {
        const text = String(value);
        if (text && text !== "[object Object]") return text;
      } catch (_) {}
    }

    return output;
  }

  function collectRecoveryStrings(value, output = [], depth = 0, seen = new WeakSet()) {
    if (value === null || value === undefined || depth > 4) return output;

    if (typeof value === "string") {
      const text = value.trim();
      if (
        text &&
        text !== "{}" &&
        text !== "[]" &&
        text !== "[object Object]" &&
        text !== "undefined" &&
        text !== "null"
      ) {
        output.push(text);
      }
      return output;
    }

    if (typeof value !== "object") {
      output.push(String(value));
      return output;
    }

    if (seen.has(value)) return output;
    seen.add(value);

    const keys = new Set([
      ...Object.keys(value),
      ...Object.getOwnPropertyNames(value)
    ]);

    for (const key of keys) {
      if (key === "stack") continue;
      try {
        collectRecoveryStrings(value[key], output, depth + 1, seen);
      } catch (_) {}
    }

    return output;
  }

  function recoveryErrorDetails(error) {
    const serialized = serializeRecoveryError(error);
    const strings = collectRecoveryStrings(error);

    const status = Number(
      error?.status ||
      error?.context?.status ||
      serialized?.status ||
      serialized?.context?.status ||
      0
    );

    const code = String(
      error?.code ||
      error?.error_code ||
      error?.context?.code ||
      serialized?.code ||
      serialized?.error_code ||
      ""
    ).trim();

    const name = String(
      error?.name ||
      serialized?.name ||
      ""
    ).trim();

    let message = "";

    const directCandidates = [
      error?.message,
      error?.error_description,
      error?.description,
      error?.details,
      error?.hint,
      error?.context?.body?.message,
      error?.context?.body?.error_description,
      error?.context?.body?.error
    ];

    for (const candidate of directCandidates) {
      if (typeof candidate === "string") {
        const text = candidate.trim();
        if (
          text &&
          text !== "{}" &&
          text !== "[]" &&
          text !== "[object Object]"
        ) {
          message = text;
          break;
        }
      }
    }

    if (!message) {
      message = strings.find(text => {
        const normalized = normalizeText(text);
        return (
          normalized.includes("rate") ||
          normalized.includes("email") ||
          normalized.includes("smtp") ||
          normalized.includes("fetch") ||
          normalized.includes("network") ||
          normalized.includes("redirect") ||
          normalized.includes("invalid") ||
          normalized.includes("auth")
        );
      }) || "";
    }

    let raw = "";
    try {
      raw = JSON.stringify(serialized);
    } catch (_) {
      raw = "";
    }

    if (
      message === "{}" ||
      message === "[]" ||
      message === "[object Object]"
    ) {
      message = "";
    }

    return {
      status,
      code,
      name,
      message,
      raw,
      normalized: normalizeText(
        `${name} ${code} ${status} ${message} ${raw}`
      )
    };
  }

  function recoveryErrorMessage(error) {
    const details = recoveryErrorDetails(error);
    const value = details.normalized;

    if (
      details.status === 429 ||
      value.includes("rate limit") ||
      value.includes("over email send rate limit") ||
      value.includes("too many requests")
    ) {
      return (
        "O limite temporário de envio de e-mails foi atingido. " +
        "Aguarde aproximadamente 1 hora e solicite somente um novo código."
      );
    }

    if (
      value.includes("failed to fetch") ||
      value.includes("network") ||
      value.includes("fetch") ||
      value.includes("connection")
    ) {
      return (
        "Não foi possível conectar ao serviço de autenticação. " +
        "Verifique a internet e tente novamente."
      );
    }

    if (
      value.includes("redirect") ||
      value.includes("url not allowed") ||
      value.includes("redirect_to")
    ) {
      return (
        "O endereço de redefinição não está autorizado no Supabase. " +
        "Confira Authentication → URL Configuration."
      );
    }

    if (
      value.includes("smtp") ||
      value.includes("email provider") ||
      value.includes("error sending") ||
      value.includes("sending recovery email")
    ) {
      return (
        "O Supabase não conseguiu enviar o e-mail. " +
        "Confira a configuração SMTP em Authentication → Emails."
      );
    }

    if (
      value.includes("invalid email") ||
      value.includes("email address is invalid")
    ) {
      return "O endereço de e-mail informado é inválido.";
    }

    if (
      value.includes("user not found") ||
      value.includes("email not found")
    ) {
      return (
        "Não foi localizada uma conta com esse e-mail. " +
        "Confira o endereço informado."
      );
    }

    if (details.message) {
      const technical = [
        details.status ? `HTTP ${details.status}` : "",
        details.code || "",
        details.name || ""
      ].filter(Boolean).join(" · ");

      return (
        `Não foi possível enviar o código: ${details.message}` +
        (technical ? ` (${technical})` : "")
      );
    }

    const technicalCode = [
      details.status ? `HTTP ${details.status}` : "",
      details.code || "",
      details.name || ""
    ].filter(Boolean).join(" · ") || "AUTH-RECOVERY-UNKNOWN";

    return (
      "Não foi possível enviar o código de redefinição. " +
      `Código: ${technicalCode}. ` +
      "A causa mais comum é limite temporário de e-mails ou SMTP não configurado."
    );
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
  function areaName(code) {
    return workAreas.find(area => area.code === code)?.name || "—";
  }

  function isRoomOnlyWorkArea(code,name="") {
    const normalizedCode=String(code||"").trim().toUpperCase();
    const normalizedName=normalizeText(name);

    return (
      ["COM","MFI"].includes(normalizedCode)||
      normalizedName==="comissionamento"||
      normalizedName==="montagem final"
    );
  }

  function enforceWorkAreaDetailType(code,name,detailType) {
    return isRoomOnlyWorkArea(code,name)
      ?"room"
      :(detailType||"none");
  }

  function areaDefinition(code) {
    const area=workAreas.find(item=>item.code===code);

    if(area){
      return {
        ...area,
        detail_type:enforceWorkAreaDetailType(
          area.code,
          area.name,
          area.detail_type
        )
      };
    }

    const legacyDetailType={
      FAB:"sector",
      MES:"module",
      MPA:"panel_type",
      MFI:"room",
      COM:"room",
      ADM:"none"
    };

    return {
      code,
      name:code||"Área",
      detail_type:legacyDetailType[code]||"none",
      active:true,
      order_index:999
    };
  }

  function areaDetailType(code) {
    return areaDefinition(code).detail_type||"none";
  }

  function areaDetailTypeLabel(value) {
    return ({
      none:"Sem referência",
      sector:"Setor",
      module:"Sala + módulo + parte",
      panel_type:"Tipo de painel",
      room:"Sala do projeto"
    })[value]||"Sem referência";
  }

  function normalizeWorkAreaCode(value) {
    return String(value||"")
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_-]+/g,"-")
      .replace(/^-+|-+$/g,"");
  }
  function sectorName(id) {
    return manufacturingSectors.find(row => row.id === id)?.name || "—";
  }
  function moduleName(id, projectId = "", roomId = "") {
    const roomLink = projectRoomModules.find(row =>
      row.project_id === projectId &&
      row.room_id === roomId &&
      row.module_id === id
    );
    const projectLink = projectModules.find(row =>
      row.project_id === projectId && row.module_id === id
    );
    return roomLink?.display_name ||
      projectLink?.display_name ||
      modules.find(row => row.id === id)?.name ||
      "—";
  }
  function roomName(id, projectId = "") {
    const link = projectRooms.find(row =>
      row.project_id === projectId && row.room_id === id
    );
    return link?.display_name || rooms.find(row => row.id === id)?.name || "—";
  }
  function panelTypeName(id) {
    return panelTypes.find(row => row.id === id)?.name || "—";
  }
  function roomInstanceName(id) {
    const instance=projectRoomInstances.find(row=>row.id===id);
    if(!instance)return "—";
    return instance.display_name || rooms.find(row=>row.id===instance.room_id)?.name || "Sala";
  }
  function roomInstanceModuleName(id) {
    const row=projectRoomInstanceModules.find(item=>item.id===id);
    return row?.display_name || row?.code || "—";
  }
  function modulePartName(value){
    return value==="inferior"?"Parte inferior":value==="superior"?"Parte superior":"—";
  }
  function entryReferenceName(entry) {
    const detailType=areaDetailType(entry.area_code);

    if(detailType==="sector")return sectorName(entry.sector_id);

    if(detailType==="module"){
      const room=entry.project_room_instance_id
        ?roomInstanceName(entry.project_room_instance_id)
        :roomName(entry.room_id,entry.project_id);
      const module=entry.project_room_instance_module_id
        ?roomInstanceModuleName(entry.project_room_instance_module_id)
        :moduleName(entry.module_id,entry.project_id,entry.room_id);
      const part=modulePartName(entry.module_part);
      return `${room} / ${module}${part!=="—"?` / ${part}`:""}`;
    }

    if(detailType==="panel_type")return panelTypeName(entry.panel_type_id);

    if(detailType==="room"){
      return entry.project_room_instance_id
        ?roomInstanceName(entry.project_room_instance_id)
        :roomName(entry.room_id,entry.project_id);
    }

    return "Não aplicável";
  }
  function activityAreas(activityId) {
    return activityAreaLinks
      .filter(link => link.activity_id === activityId)
      .map(link => link.area_code);
  }

  function applyConfirmedActivityAreas(activityId, areaCodes = []) {
    const normalizedCodes=[...new Set(
      (Array.isArray(areaCodes)?areaCodes:[])
        .map(code=>String(code||"").trim().toUpperCase())
        .filter(Boolean)
    )];

    activityAreaLinks=activityAreaLinks.filter(
      link=>link.activity_id!==activityId
    );

    normalizedCodes.forEach(area_code=>{
      activityAreaLinks.push({
        activity_id:activityId,
        area_code
      });
    });

    return normalizedCodes;
  }

  async function loadGroupedActivityAreaLinks() {
    const {data,error}=await sb.rpc(
      "aponta_list_activity_areas_grouped_v2183"
    );

    if(error){
      return {data:null,error};
    }

    const links=[];

    (data||[]).forEach(row=>{
      const activityId=row.activity_id;
      const areaCodes=Array.isArray(row.area_codes)
        ?row.area_codes
        :[];

      areaCodes.forEach(area_code=>{
        const normalized=String(area_code||"").trim().toUpperCase();
        if(!activityId||!normalized)return;

        links.push({
          activity_id:activityId,
          area_code:normalized
        });
      });
    });

    return {
      data:links,
      groupedRows:(data||[]).length,
      linkCount:links.length,
      error:null
    };
  }

  async function loadAllProjects() {
    const allProjects=[];
    const pageSize=500;
    let from=0;

    while(true){
      const {data,error}=await sb
        .from("projects")
        .select("*")
        .order("name",{ascending:true})
        .order("id",{ascending:true})
        .range(from,from+pageSize-1);

      if(error)return {data:null,error};

      const page=data||[];
      allProjects.push(...page);

      if(page.length<pageSize)break;
      from+=pageSize;
    }

    return {data:allProjects,error:null};
  }

  async function loadBaseData() {
    const [p, pr, ac, ho, wa, ms, mo, ro, pt, aal, pm, pro, prm, pri, prim] = await Promise.all([
      sb.from("profiles").select("*").order("full_name"),
      loadAllProjects(),
      sb.from("activities").select("*").order("name"),
      sb.from("holidays").select("*").order("holiday_date"),
      sb.from("work_areas").select("*").order("order_index"),
      sb.from("manufacturing_sectors").select("*").order("order_index"),
      sb.from("modules").select("*").order("order_index"),
      sb.from("rooms").select("*").order("order_index"),
      sb.from("panel_types").select("*").order("order_index"),
      loadGroupedActivityAreaLinks(),
      sb.from("project_modules").select("*").order("order_index"),
      sb.from("project_rooms").select("*").order("order_index"),
      sb.from("project_room_modules").select("*").order("order_index"),
      sb.from("project_room_instances").select("*").order("order_index"),
      sb.from("project_room_instance_modules").select("*").order("order_index")
    ]);
    for (const result of [p,pr,ac,ho]) if (result.error) throw result.error;
    if(aal.error){
      throw new Error(
        "Não foi possível carregar todas as áreas vinculadas às atividades. " +
        "Execute o SQL obrigatório da versão 2.18.3 no Supabase."
      );
    }

    for (const result of [wa,ms,mo,ro,pt,pm,pro,prm,pri,prim]) {
      if (result.error) {
        throw new Error(
          "Estrutura Projeto > Sala > Módulo não instalada. " +
          "Execute ATUALIZAR_BANCO_v2.16_SALAS_MULTIPLAS_PARTES_MODULO.sql no Supabase."
        );
      }
    }
    profiles=p.data||[];
    projects=pr.data||[];
    activities=(ac.data||[]).map(activity=>({
      ...activity,
      code:normalizeActivityCode(activity.code),
      observation_requirement:normalizeObservationRequirement(activity.observation_requirement)
    }));
    holidays=ho.data||[];
    workAreas=wa.data||[]; manufacturingSectors=ms.data||[]; modules=mo.data||[];
    rooms=ro.data||[];
    panelTypes=pt.data||[];

    const uniqueActivityAreaLinks=new Map();
    (aal.data||[]).forEach(link=>{
      const activityId=String(link.activity_id||"").trim();
      const areaCode=String(link.area_code||"").trim().toUpperCase();
      if(!activityId||!areaCode)return;

      uniqueActivityAreaLinks.set(
        `${activityId}|${areaCode}`,
        {
          activity_id:activityId,
          area_code:areaCode
        }
      );
    });
    activityAreaLinks=[...uniqueActivityAreaLinks.values()];

    projectModules=pm.data||[]; projectRooms=pro.data||[]; projectRoomModules=prm.data||[];
    projectRoomInstances=pri.data||[]; projectRoomInstanceModules=prim.data||[];
    me = profiles.find(x => x.id === session.user.id);
    if (!me) throw new Error("Seu perfil ainda não foi criado. Atualize a página em alguns segundos.");
    if (!me.active) throw new Error("Seu usuário está inativo. Fale com o administrador.");
    console.info(
      "Aponta Horas — áreas das atividades carregadas:",
      {
        atividades:activities.length,
        atividadesComAreas:new Set(
          activityAreaLinks.map(link=>link.activity_id)
        ).size,
        vinculos:activityAreaLinks.length
      }
    );

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

  function optionsWithPlaceholder(rows, labelFn = row => row.name, valueFn = row => row.id, placeholder = "Selecione...") {
    return `<option value="">${esc(placeholder)}</option>` + rows.map(row =>
      `<option value="${esc(valueFn(row))}">${esc(labelFn(row))}</option>`
    ).join("");
  }

  function activeRows(rows) { return rows.filter(row => row.active !== false); }

  function projectRoomOptions(projectId) {
    return projectRoomInstances
      .filter(row=>row.project_id===projectId&&row.active!==false)
      .sort((a,b)=>(a.order_index||0)-(b.order_index||0)||(a.instance_number||0)-(b.instance_number||0))
      .map(row=>({id:row.id,room_id:row.room_id,name:row.display_name||`${rooms.find(room=>room.id===row.room_id)?.name||"Sala"} ${String(row.instance_number).padStart(2,"0")}`}));
  }

  function roomInstanceDefinition(roomInstanceId) {
    const instance=projectRoomInstances.find(row=>row.id===roomInstanceId);
    if(!instance)return null;
    return standardRoomDefinitionFor(rooms.find(room=>room.id===instance.room_id));
  }

  function isMonoblockRoomInstance(roomInstanceId) {
    return roomInstanceDefinition(roomInstanceId)?.monoblock===true;
  }

  function projectRoomModuleOptions(projectId, roomInstanceId) {
    if(!projectId||!roomInstanceId)return [];
    const instance=projectRoomInstances.find(row=>row.id===roomInstanceId&&row.project_id===projectId);
    if(!instance)return [];
    return projectRoomInstanceModules
      .filter(row=>row.room_instance_id===roomInstanceId&&row.active!==false)
      .sort((a,b)=>(a.order_index||0)-(b.order_index||0)||(a.module_number||0)-(b.module_number||0))
      .map(row=>({id:row.id,name:row.display_name||row.code||`Módulo ${row.module_number}`,has_lower_part:row.has_lower_part,has_upper_part:row.has_upper_part}));
  }

  function setEntryStepNumbers(prefix, areaCode) {
    if(prefix!=="entry")return;
    const detailType=areaDetailType(areaCode);
    const structural=detailType==="module";
    const noDetail=detailType==="none";
    const monoblock=structural&&isMonoblockRoomInstance($("entryRoom")?.value);

    if($("entryRoomStep"))$("entryRoomStep").textContent="3";
    if($("entryModuleStep"))$("entryModuleStep").textContent="4";
    if($("entryModulePartStep"))$("entryModulePartStep").textContent="5";
    if($("entrySectorStep"))$("entrySectorStep").textContent="3";
    if($("entryPanelTypeStep"))$("entryPanelTypeStep").textContent="3";
    if($("entryActivityStep")){
      $("entryActivityStep").textContent=structural
        ?(monoblock?"5":"6")
        :noDetail?"3":"4";
    }
  }

  function refreshModulePart(prefix,selectedPart=""){
    const moduleId=$(prefix+"Module")?.value;
    const roomInstanceId=$(prefix+"Room")?.value;
    const select=$(prefix+"ModulePart");
    const field=$(prefix+"ModulePartField");
    if(!select)return;

    const structural=areaDetailType($(prefix+"Area")?.value)==="module";
    const monoblock=structural&&isMonoblockRoomInstance(roomInstanceId);

    if(monoblock){
      if(field)field.hidden=true;
      select.innerHTML='<option value="">Não se aplica ao MONOBLOCO</option>';
      select.value="";
      select.required=false;
      select.disabled=true;
      setEntryStepNumbers(prefix,$(prefix+"Area")?.value||"");
      return;
    }

    if(field)field.hidden=!structural;
    select.required=structural;

    const module=projectRoomInstanceModules.find(row=>row.id===moduleId);
    const options=['<option value="">Selecione a parte</option>'];
    if(module?.has_lower_part!==false)options.push('<option value="inferior">Parte inferior</option>');
    if(module?.has_upper_part!==false)options.push('<option value="superior">Parte superior</option>');
    select.innerHTML=options.join("");
    select.disabled=!moduleId;
    if(selectedPart)select.value=selectedPart;
    setEntryStepNumbers(prefix,$(prefix+"Area")?.value||"");
  }

  function refreshStructuralModule(prefix, selectedModuleId = "", selectedPart="") {
    const projectId=$(prefix+"Project").value;
    const roomInstanceId=$(prefix+"Room").value;
    const select=$(prefix+"Module");
    if(!select)return;
    const rows=projectRoomModuleOptions(projectId,roomInstanceId);
    select.innerHTML=optionsWithPlaceholder(rows,row=>row.name,row=>row.id,roomInstanceId?"Selecione o módulo da sala":"Selecione primeiro a sala");
    select.disabled=!roomInstanceId;
    if(selectedModuleId)select.value=selectedModuleId;
    refreshModulePart(prefix,selectedPart);
  }

  function setConditionalField(prefix, areaCode, selected = {}) {
    const projectId=$(prefix+"Project").value;
    const detailType=areaDetailType(areaCode);
    const showSector=detailType==="sector";
    const showPanel=detailType==="panel_type";
    const showRoom=detailType==="module"||detailType==="room";
    const showModule=detailType==="module";
    const showPart=detailType==="module";

    const visibility={
      Sector:showSector,
      PanelType:showPanel,
      Room:showRoom,
      Module:showModule,
      ModulePart:showPart
    };

    Object.entries(visibility).forEach(([suffix,show])=>{
      const field=$(prefix+suffix+"Field");
      const select=$(prefix+suffix);
      if(!field||!select)return;

      field.hidden=!show;
      select.required=show;

      if(!show){
        select.value="";
        select.disabled=false;
      }
    });

    if($(prefix+"RoomLabel")){
      $(prefix+"RoomLabel").textContent=detailType==="module"
        ?`Sala específica — ${areaName(areaCode)}`
        :`Sala do projeto — ${areaName(areaCode)}`;
    }

    if(showSector){
      const select=$(prefix+"Sector");
      select.innerHTML=optionsWithPlaceholder(
        activeRows(manufacturingSectors),
        row=>row.name,
        row=>row.id,
        "Selecione o setor"
      );
      if(selected.sector_id)select.value=selected.sector_id;
    }

    if(showPanel){
      const select=$(prefix+"PanelType");
      select.innerHTML=optionsWithPlaceholder(
        activeRows(panelTypes),
        row=>row.name,
        row=>row.id,
        "Selecione o tipo de painel"
      );
      if(selected.panel_type_id)select.value=selected.panel_type_id;
    }

    if(showRoom){
      const roomSelect=$(prefix+"Room");
      const roomRows=projectRoomOptions(projectId);
      roomSelect.innerHTML=optionsWithPlaceholder(
        roomRows,
        row=>row.name,
        row=>row.id,
        projectId?"Selecione a sala específica":"Selecione primeiro o projeto"
      );
      roomSelect.disabled=!projectId;
      if(selected.project_room_instance_id){
        roomSelect.value=selected.project_room_instance_id;
      }
    }

    if(showModule){
      refreshStructuralModule(
        prefix,
        selected.project_room_instance_module_id||"",
        selected.module_part||""
      );
    }

    setEntryStepNumbers(prefix,areaCode);
  }

  function filteredEntryActivities(areaCode) {
    if (!areaCode) return [];
    const ids=new Set(activityAreaLinks.filter(link=>link.area_code===areaCode).map(link=>link.activity_id));
    return activities.filter(activity=>activity.active && ids.has(activity.id));
  }

  function setActivityOptions(prefix, selectedActivityId = "") {
    const areaCode=$(prefix+"Area").value;
    const rows=filteredEntryActivities(areaCode);
    const select=$(prefix+"Activity");
    select.innerHTML=optionsWithPlaceholder(rows,row=>`${row.code?row.code+" — ":""}${row.name}`,row=>row.id,areaCode?"Selecione a atividade":"Selecione primeiro a área");
    select.disabled=!areaCode;
    if (selectedActivityId) select.value=selectedActivityId;
    updateActivityHelp(prefix);
  }

  function updateActivityHelp(prefix) {
    const activity=activities.find(row=>row.id===$(prefix+"Activity").value);
    const box=$(prefix+"ActivityHelp");
    const details=$(prefix+"Details");
    const rule=$(prefix+"ObservationRule");
    if (!activity) {
      if (box) box.hidden=true;
      if (details) details.required=false;
      if (rule) {
        rule.textContent="Opcional";
        rule.classList.remove("required");
      }
      return;
    }
    const required=normalizeObservationRequirement(
      activity.observation_requirement
    )==="Obrigatória";

    details.required=required;
    rule.textContent=required?"Obrigatória":"Opcional";
    rule.classList.toggle("required",required);

    if (box) {
      box.hidden=false;
      box.innerHTML=`<strong>${esc(activity.discipline_name||"Atividade")}</strong><span>${esc(activity.usage_description||"Registre objetivamente a ação e o resultado.")}</span>`;
    }
    details.placeholder=activity.usage_description||"Descreva a ação executada e o resultado.";
  }

  function refreshEntryFlow(prefix, selected = {}) {
    const areaCode=$(prefix+"Area").value;
    setConditionalField(prefix,areaCode,selected);
    setActivityOptions(prefix,selected.activity_id||"");
  }

  function entryFlowPayload(prefix) {
    const areaCode=$(prefix+"Area").value;
    const detailType=areaDetailType(areaCode);
    const usesRoom=["module","room"].includes(detailType);
    const instanceId=usesRoom?$(prefix+"Room").value:null;
    const moduleInstanceId=detailType==="module"?$(prefix+"Module").value:null;
    const instance=projectRoomInstances.find(row=>row.id===instanceId);
    const module=projectRoomInstanceModules.find(row=>row.id===moduleInstanceId);
    const monoblock=detailType==="module"&&isMonoblockRoomInstance(instanceId);

    return {
      area_code:areaCode,
      sector_id:detailType==="sector"?$(prefix+"Sector").value:null,
      room_id:instance?.room_id||null,
      module_id:module?.legacy_module_id||null,
      panel_type_id:detailType==="panel_type"?$(prefix+"PanelType").value:null,
      project_room_instance_id:instanceId||null,
      project_room_instance_module_id:moduleInstanceId||null,
      module_part:detailType==="module"&&!monoblock
        ?$(prefix+"ModulePart").value
        :null
    };
  }

  function validateEntryFlow(prefix) {
    const area=$(prefix+"Area").value;
    if(!area){
      toast("Selecione a área do apontamento.",true);
      $(prefix+"Area").focus();
      return false;
    }

    const detailType=areaDetailType(area);

    if(detailType==="sector"&&!$(prefix+"Sector").value){
      toast(`Selecione o setor para ${areaName(area)}.`,true);
      $(prefix+"Sector").focus();
      return false;
    }

    if(detailType==="module"){
      if(!$(prefix+"Room").value){
        toast(`Selecione a sala para ${areaName(area)}.`,true);
        $(prefix+"Room").focus();
        return false;
      }

      if(!$(prefix+"Module").value){
        toast("Selecione o módulo da sala.",true);
        $(prefix+"Module").focus();
        return false;
      }

      const monoblock=isMonoblockRoomInstance($(prefix+"Room").value);
      if(!monoblock&&!$(prefix+"ModulePart").value){
        toast("Selecione a parte inferior ou superior do módulo.",true);
        $(prefix+"ModulePart").focus();
        return false;
      }
    }

    if(detailType==="panel_type"&&!$(prefix+"PanelType").value){
      toast(`Selecione o tipo de painel para ${areaName(area)}.`,true);
      $(prefix+"PanelType").focus();
      return false;
    }

    if(detailType==="room"&&!$(prefix+"Room").value){
      toast(`Selecione a sala para ${areaName(area)}.`,true);
      $(prefix+"Room").focus();
      return false;
    }
    const selectedActivityId=$(prefix+"Activity").value;
    if (!selectedActivityId) {
      toast("Selecione a atividade.",true);
      $(prefix+"Activity").focus();
      return false;
    }

    const activityBelongsToSelectedArea=activityAreaLinks.some(link=>
      String(link.activity_id||"")===String(selectedActivityId||"")&&
      String(link.area_code||"").trim().toUpperCase()===
        String(area||"").trim().toUpperCase()
    );

    if(!activityBelongsToSelectedArea){
      toast(
        "A atividade selecionada não pertence à área informada. "+
        "Escolha uma atividade exibida para esta área.",
        true
      );
      $(prefix+"Activity").focus();
      return false;
    }

    if (
      $(prefix+"Details").required &&
      !$(prefix+"Details").value.trim()
    ) {
      toast("A observação é obrigatória para esta atividade.",true);
      $(prefix+"Details").focus();
      return false;
    }

    return true;
  }

  function renderActivityAreaCheckboxes(containerId, selectedCodes = []) {
    const selected=new Set(selectedCodes);
    const container=$(containerId);
    if (!container) return;

    container.innerHTML=activeRows(workAreas).map(area=>`
      <label class="activity-area-option">
        <input
          type="checkbox"
          value="${esc(area.code)}"
          ${selected.has(area.code)?"checked":""}>
        <span>
          <strong>${esc(area.name)}</strong>
          <small>${esc(area.code)}</small>
        </span>
      </label>
    `).join("");

    refreshActivityAreaOptionStyles(containerId);
  }

  function refreshActivityAreaOptionStyles(containerId){
    const container=$(containerId);
    if(!container)return;

    container.querySelectorAll(".activity-area-option").forEach(label=>{
      const input=label.querySelector('input[type="checkbox"]');
      label.classList.toggle("selected",Boolean(input?.checked));
    });
  }

  function checkedAreaCodes(containerId) {
    return [...$(containerId).querySelectorAll('input[type="checkbox"]:checked')]
      .map(input=>input.value);
  }

  function setAllActivityAreas(containerId,checked){
    const container=$(containerId);
    if(!container)return;

    container.querySelectorAll('input[type="checkbox"]').forEach(input=>{
      input.checked=checked;
    });

    refreshActivityAreaOptionStyles(containerId);
  }

  ["activityAreasCheckboxes","editActivityAreasCheckboxes"].forEach(containerId=>{
    const container=$(containerId);
    if(!container)return;

    container.addEventListener("change",event=>{
      if(event.target.matches('input[type="checkbox"]')){
        refreshActivityAreaOptionStyles(containerId);
      }
    });
  });

  function fillProjectStructureSelects() {
    const projectOptions=optionsWithPlaceholder(activeRows(projects),row=>row.code?`${row.code} — ${row.name}`:row.name,row=>row.id,"Selecione o projeto");
    ["projectCompositionProject","projectRoomModuleProject"].forEach(id=>{
      const select=$(id);
      if(!select)return;
      const old=select.value;
      select.innerHTML=projectOptions;
      if(old&&activeRows(projects).some(row=>row.id===old))select.value=old;
      else select.value="";
    });

    const composition=$("projectCompositionProject");
    const moduleProject=$("projectRoomModuleProject");
    if(moduleProject&&composition?.value)moduleProject.value=composition.value;

    const roomCatalog=$("projectRoomInstanceRoom");
    if(roomCatalog){
      const old=roomCatalog.value;
      roomCatalog.innerHTML=optionsWithPlaceholder(activeRows(rooms),row=>`${row.code?row.code+" — ":""}${row.name}`,row=>row.id,"Selecione o tipo de sala");
      if(old&&activeRows(rooms).some(row=>row.id===old))roomCatalog.value=old;
      else roomCatalog.value="";
    }

    refreshProjectRoomModuleRoomSelect();
    renderProjectComposition();
    renderProjectStructureTables();
  }

  function updateModulePartsEditorForInstance(instanceId,editMode=false){
    const editor=$(editMode?"editProjectRoomModulePartsEditor":"projectRoomModulePartsEditor");
    const lower=$(editMode?"editProjectRoomModuleLower":"projectRoomModuleLower");
    const upper=$(editMode?"editProjectRoomModuleUpper":"projectRoomModuleUpper");
    if(!editor||!lower||!upper)return;

    const hasInstance=Boolean(instanceId);
    const monoblock=hasInstance&&isMonoblockRoomInstance(instanceId);

    editor.hidden=!hasInstance||monoblock;
    lower.disabled=!hasInstance||monoblock;
    upper.disabled=!hasInstance||monoblock;

    if(monoblock){
      lower.checked=false;
      upper.checked=false;
    }else if(hasInstance&&!editMode&&!lower.checked&&!upper.checked){
      lower.checked=true;
      upper.checked=true;
    }
  }

  function refreshProjectRoomModuleRoomSelect() {
    const projectSelect=$("projectRoomModuleProject");const roomSelect=$("projectRoomModuleRoom");if(!projectSelect||!roomSelect)return;
    const old=roomSelect.value;const rows=projectRoomOptions(projectSelect.value);
    roomSelect.innerHTML=optionsWithPlaceholder(rows,row=>row.name,row=>row.id,projectSelect.value?"Selecione a sala específica":"Selecione primeiro o projeto");
    roomSelect.disabled=!projectSelect.value;
    if(old&&rows.some(row=>row.id===old))roomSelect.value=old;
    else roomSelect.value="";
    updateModulePartsEditorForInstance(roomSelect.value,false);
  }

  function fillSelects() {
    const activeProfiles=profiles.filter(p=>p.active);
    const approvedProfiles=activeProfiles.filter(p=>canMakeEntries(p));
    ["entryUser","closingUser"].forEach(id=>{const el=$(id);const old=el.value;el.innerHTML=optionList(approvedProfiles);el.value=isManager()?(old||me.id):me.id;if(!isManager())el.disabled=true;});
    ["absenceUser"].forEach(id=>{const el=$(id);const old=el.value;el.innerHTML=optionList(activeProfiles);el.value=isManager()?(old||me.id):me.id;if(!isManager())el.disabled=true;});
    ["filterEntryUser","reportUser","absenceFilterUser","peopleReportUser","closingHistoryUser"].forEach(id=>{const el=$(id);if(!el)return;const old=el.value;el.innerHTML=optionList(activeProfiles,true);el.value=isManager()?old:me.id;if(!isManager())el.disabled=true;});

    ["entryProject","editEntryProject"].forEach(id=>$(id).innerHTML=optionsWithPlaceholder(activeRows(projects),row=>row.code?`${row.code} — ${row.name}`:row.name,row=>row.id,"Selecione o projeto"));
    $("reportProject").innerHTML=optionList(projects,true);
    if($("closingHistoryProject")){
      $("closingHistoryProject").innerHTML='<option value="">Todos os projetos</option>'+activeRows(projects).map(row=>`<option value="${row.id}">${esc(row.code?`${row.code} — ${row.name}`:row.name)}</option>`).join("");
    }
    ["entryArea","editEntryArea"].forEach(id=>$(id).innerHTML=optionsWithPlaceholder(activeRows(workAreas),row=>row.name,row=>row.code,"Selecione a área"));
    fillProjectStructureSelects();
    renderActivityAreaCheckboxes("activityAreasCheckboxes");
    refreshEntryFlow("entry");
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
    if($("closingHistoryStartMonth")) $("closingHistoryStartMonth").value ||= `${monthNow().slice(0,4)}-01`;
    if($("closingHistoryEndMonth")) $("closingHistoryEndMonth").value ||= monthNow();
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
        "O link de autenticação não pôde ser concluído.\n\n" +
        decodeURIComponent(authError) +
        "\n\nSolicite um novo e-mail de recuperação e confira as URLs em Authentication → URL Configuration.",
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
    const button = $("forgotPasswordBtn");
    const email = $("loginEmail").value.trim().toLowerCase();

    clearAuthMessage();

    if (!email) {
      showAuthMessage(
        "Informe seu e-mail no campo acima para receber o código de redefinição.",
        true
      );
      $("loginEmail").focus();
      return;
    }

    if (!$("loginEmail").checkValidity()) {
      showAuthMessage("Informe um endereço de e-mail válido.", true);
      $("loginEmail").focus();
      return;
    }

    const originalText = button.textContent;
    button.disabled = true;
    button.textContent = "Enviando código...";

    showAuthMessage(
      "Solicitando o código de redefinição. Aguarde o recebimento do e-mail..."
    );

    try {
      const { error } = await sb.auth.resetPasswordForEmail(email);

      if (error) throw error;

      sessionStorage.setItem("aponta_recovery_email", email);

      showAuthMessage(
        "Código enviado. Ao receber o e-mail, informe os 8 dígitos na próxima tela. " +
        "Use somente o código do e-mail mais recente."
      );

      button.textContent = "Código enviado";

      window.setTimeout(() => {
        window.location.href = recoveryPageUrl();
      }, 900);
    } catch (error) {
      console.error(
        "Erro ao solicitar código de redefinição de senha:",
        error,
        recoveryErrorDetails(error)
      );

      showAuthMessage(
        recoveryErrorMessage(error),
        true
      );

      button.disabled = false;
      button.textContent = originalText;
    }
  };  $("logoutBtn").onclick = async () => { await sb.auth.signOut(); location.reload(); };

  $("mainNav").onclick = async (e) => {
    const btn = e.target.closest("button[data-page]");
    if (!btn) return;
    const previousPage=document.querySelector("#mainNav button.active")?.dataset.page||"";
    if(previousPage==="catalogs"&&btn.dataset.page!=="catalogs"){
      resetProjectStructureSelection();
    }
    if (btn.hasAttribute("data-entry-approval-required") && !canMakeEntries()) {
      toast("Aguarde a aprovação do Gestor ou Administrador para acessar os apontamentos.", true);
      return;
    }
    document.querySelectorAll("#mainNav button").forEach(x => {
      const active=x===btn;
      x.classList.toggle("active",active);
      if(active)x.setAttribute("aria-current","page");
      else x.removeAttribute("aria-current");
    });
    btn.scrollIntoView({behavior:"smooth",block:"nearest",inline:"center"});
    document.querySelectorAll(".page").forEach(x => x.classList.toggle("active", x.id === btn.dataset.page));
    if (btn.dataset.page === "dashboard") await renderDashboard();
    if (btn.dataset.page === "entries") await renderEntries();
    if (btn.dataset.page === "absences") await renderAbsences();
    if (btn.dataset.page === "closing") await renderActiveClosingView();
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

  function updateEntryBulkActions(){
    const count=selectedEntryIds.size;
    const countElement=$("selectedEntriesCount");
    const clearButton=$("clearSelectedEntriesBtn");
    const deleteButton=$("deleteSelectedEntriesBtn");
    const selectAll=$("selectAllVisibleEntries");

    if(countElement){
      countElement.textContent=`${count} selecionado${count===1?"":"s"}`;
    }

    if(clearButton)clearButton.disabled=count===0;
    if(deleteButton)deleteButton.disabled=count===0;

    if(selectAll){
      const selectedVisible=visibleEditableEntryIds.filter(id=>selectedEntryIds.has(id)).length;
      selectAll.checked=visibleEditableEntryIds.length>0&&selectedVisible===visibleEditableEntryIds.length;
      selectAll.indeterminate=selectedVisible>0&&selectedVisible<visibleEditableEntryIds.length;
      selectAll.disabled=visibleEditableEntryIds.length===0;
    }
  }

  function clearEntrySelection(){
    selectedEntryIds.clear();
    document.querySelectorAll("[data-select-entry]").forEach(input=>{
      input.checked=false;
    });
    updateEntryBulkActions();
  }

  async function deleteTimeEntryById(id){
    const {error}=await sb.rpc("aponta_delete_time_entry_v28",{p_id:id});
    if(error)throw error;
  }

  async function selectEntries(start, end, userId = "", projectId = "") {
    const {data,error}=await sb.rpc(
      "aponta_select_time_entries_v2187",
      {
        p_start_date:start,
        p_end_date:end,
        p_user_id:userId||null,
        p_project_id:projectId||null
      }
    );

    if(error){
      const message=String(error.message||"");

      if(
        message.includes("aponta_select_time_entries_v2187")||
        message.includes("Could not find the function")||
        message.includes("function public.aponta_select_time_entries_v2187")
      ){
        throw new Error(
          "Consulta geral de apontamentos não instalada. " +
          "Execute o SQL obrigatório da versão 2.18.7 no Supabase."
        );
      }

      throw error;
    }

    return (data||[]).sort((a,b)=>{
      const dateComparison=String(b.entry_date||"").localeCompare(
        String(a.entry_date||"")
      );

      if(dateComparison)return dateComparison;

      return String(b.created_at||"").localeCompare(
        String(a.created_at||"")
      );
    });
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
      if (!validateEntryFlow("entry")) return;

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
  $("entryProject").onchange=()=>refreshEntryFlow("entry");
  $("entryArea").onchange=()=>refreshEntryFlow("entry");
  $("entryRoom").onchange=()=>{
    if(areaDetailType($("entryArea").value)==="module"){
      refreshStructuralModule("entry");
    }
  };
  $("entryModule").onchange=()=>refreshModulePart("entry");
  $("entryActivity").onchange=()=>updateActivityHelp("entry");
  $("editEntryProject").onchange=()=>refreshEntryFlow("editEntry");
  $("editEntryArea").onchange=()=>refreshEntryFlow("editEntry");
  $("editEntryRoom").onchange=()=>{
    if(areaDetailType($("editEntryArea").value)==="module"){
      refreshStructuralModule("editEntry");
    }
  };
  $("editEntryModule").onchange=()=>refreshModulePart("editEntry");
  $("editEntryActivity").onchange=()=>updateActivityHelp("editEntry");

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
        ...entryFlowPayload("entry"),
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
      const rows = await selectEntries(
        $("filterEntryStart").value || firstDay(),
        $("filterEntryEnd").value || lastDay(),
        user
      );

      visibleEditableEntryIds=rows
        .filter(x=>isManager()||(x.user_id===me.id&&["rascunho","devolvido"].includes(x.status)))
        .map(x=>x.id);

      const visibleIds=new Set(rows.map(x=>x.id));
      Array.from(selectedEntryIds).forEach(id=>{
        if(!visibleIds.has(id)||!visibleEditableEntryIds.includes(id)){
          selectedEntryIds.delete(id);
        }
      });

      $("entriesTable").innerHTML = rows.map(x => {
        const editable=isManager()||(x.user_id===me.id&&["rascunho","devolvido"].includes(x.status));
        return `<tr>
          <td>
            ${editable
              ?`<input class="entry-row-selector" type="checkbox" data-select-entry="${x.id}" ${selectedEntryIds.has(x.id)?"checked":""} aria-label="Selecionar apontamento de ${dateBR(x.entry_date)}">`
              :'<span title="Apontamento bloqueado">—</span>'}
          </td>
          <td>${dateBR(x.entry_date)}</td>
          <td>${esc(profileName(x.user_id))}</td>
          <td>${esc(projectName(x.project_id))}</td>
          <td>${esc(areaName(x.area_code))}</td>
          <td>${esc(entryReferenceName(x))}</td>
          <td>${esc(activityName(x.activity_id))}</td>
          <td>${fmt(x.hours)}</td>
          <td><span class="badge status-${x.status}">${statusLabel(x.status)}</span></td>
          <td>
            ${editable
              ?`<div class="table-actions">
                  <button class="btn secondary small" data-edit-entry="${x.id}">Editar</button>
                  <button class="btn danger small" data-delete-entry="${x.id}">Excluir</button>
                </div>`
              :"—"}
          </td>
        </tr>`;
      }).join("") || '<tr><td colspan="10" class="empty">Nenhum apontamento encontrado</td></tr>';

      updateEntryBulkActions();
      await updateDayTotal();
    } catch (e) {
      handleError(e);
    }
  }

  $("filterEntriesBtn").onclick = async ()=>{
    clearEntrySelection();
    await renderEntries();
  };

  $("entriesTable").onclick = async (e) => {
    const selector=e.target.closest("[data-select-entry]");
    if(selector){
      const id=selector.dataset.selectEntry;
      if(selector.checked)selectedEntryIds.add(id);
      else selectedEntryIds.delete(id);
      updateEntryBulkActions();
      return;
    }

    const editId = e.target.dataset.editEntry;
    const deleteId = e.target.dataset.deleteEntry;
    if (editId) {
      const {data, error} = await sb.from("time_entries").select("*").eq("id", editId).single();
      if (error) return handleError(error);
      $("editEntryId").value = data.id;
      $("editEntryDate").value = data.entry_date;
      $("editEntryHours").value = data.hours;
      $("editEntryProject").value=data.project_id;
      let areaCode=data.area_code;
      if(!areaCode) areaCode=activityAreas(data.activity_id)[0]||"ADM";
      $("editEntryArea").value=areaCode;
      refreshEntryFlow("editEntry",data);
      $("editEntryActivity").value=data.activity_id;
      $("editEntryDetails").value=data.details;
      updateActivityHelp("editEntry");
      $("editEntryDialog").showModal();
    }
    if (deleteId && confirm("Excluir este apontamento?")) {
      showLoading(true);
      try {
        await deleteTimeEntryById(deleteId);
        selectedEntryIds.delete(deleteId);
        toast("Apontamento excluído.");
        await Promise.all([renderEntries(), renderDashboard()]);
      } catch(error) {
        handleError(error, "Não foi possível excluir. Períodos enviados ou aprovados precisam ser reabertos.");
      } finally { showLoading(false); }
    }
  };

  $("selectAllVisibleEntries").onchange=e=>{
    visibleEditableEntryIds.forEach(id=>{
      if(e.target.checked)selectedEntryIds.add(id);
      else selectedEntryIds.delete(id);
    });

    document.querySelectorAll("[data-select-entry]").forEach(input=>{
      input.checked=e.target.checked;
    });

    updateEntryBulkActions();
  };

  $("clearSelectedEntriesBtn").onclick=clearEntrySelection;

  $("deleteSelectedEntriesBtn").onclick=async ()=>{
    const ids=Array.from(selectedEntryIds);
    if(!ids.length)return;

    const confirmed=window.confirm(
      `Excluir ${ids.length} apontamento${ids.length===1?"":"s"} selecionado${ids.length===1?"":"s"}?\n\n`+
      "Apontamentos aprovados, enviados ou pertencentes a períodos fechados podem ser bloqueados."
    );
    if(!confirmed)return;

    showLoading(true);
    let deleted=0;
    const blocked=[];

    try{
      for(const id of ids){
        try{
          await deleteTimeEntryById(id);
          deleted+=1;
          selectedEntryIds.delete(id);
        }catch(error){
          blocked.push({
            id,
            message:error?.message||"Exclusão bloqueada."
          });
        }
      }

      await Promise.all([renderEntries(),renderDashboard(),updateDayTotal()]);

      if(blocked.length){
        const message=[
          `${deleted} apontamento${deleted===1?"":"s"} excluído${deleted===1?"":"s"}.`,
          `${blocked.length} não ${blocked.length===1?"pôde":"puderam"} ser excluído${blocked.length===1?"":"s"} por bloqueio de aprovação ou fechamento.`
        ].join(" ");
        toast(message,true);
        console.warn("Apontamentos não excluídos",blocked);
      }else{
        toast(`${deleted} apontamento${deleted===1?"":"s"} excluído${deleted===1?"":"s"}.`);
      }
    }finally{
      showLoading(false);
      updateEntryBulkActions();
    }
  };

  $("saveEditEntryBtn").onclick = async (e) => {
    e.preventDefault();

    if (!validateEntryFlow("editEntry")) return;

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
        ...entryFlowPayload("editEntry"),
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
      const copies=source.map(x=>({user_id:userId,entry_date:target,project_id:x.project_id,activity_id:x.activity_id,area_code:x.area_code,sector_id:x.sector_id,module_id:x.module_id,room_id:x.room_id,panel_type_id:x.panel_type_id,project_room_instance_id:x.project_room_instance_id,project_room_instance_module_id:x.project_room_instance_module_id,module_part:x.module_part,hours:x.hours,details:x.details,status:"rascunho"}));
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
      const userId=isManager()?$("closingUser").value:me.id;
      const month=$("closingMonth").value||monthNow();
      if(!userId)return;

      const startDate=firstDay(month);
      const endDate=lastDay(month);

      const [rows,approvedAbsences]=await Promise.all([
        selectEntries(startDate,endDate,userId),
        loadApprovedAbsencesForPeriod(startDate,endDate,userId)
      ]);

      const pointedHours=rows.reduce(
        (sum,row)=>sum+Number(row.hours||0),
        0
      );
      const planned=plannedHoursSummary(
        userId,
        month,
        approvedAbsences
      );
      const balance=closingBalance(
        pointedHours,
        planned.planned_hours
      );
      const conference=closingConference(balance);

      $("closingPlannedHours").textContent=fmt(planned.planned_hours);
      $("closingHours").textContent=fmt(pointedHours);
      $("closingBalance").textContent=signedHours(balance);
      $("closingBalance").className=`closing-balance-${conference.key}`;

      if($("closingPlanDetails")){
        $("closingPlanDetails").textContent=
          `${plannedHoursDetail(planned)}. ${conference.detail}.`;
      }

      const {data,error}=await sb
        .from("monthly_closings")
        .select("*")
        .eq("user_id",userId)
        .eq("month_ref",startDate)
        .maybeSingle();

      if(error)throw error;
      currentClosing=data;
      $("closingStatus").textContent=statusLabel(data?.status||"aberto");
      $("closingNote").value=data?.review_note||"";
      $("submitClosingBtn").disabled=
        !!data&&["enviado","aprovado"].includes(data.status);
      $("approveClosingBtn").disabled=
        !data||data.status!=="enviado";
      $("rejectClosingBtn").disabled=
        !data||data.status!=="enviado";

      const approvedForAdministrativeReturn=
        isAdmin()&&data?.status==="aprovado";
      const adminReturnPanel=$("adminApprovedReturnPanel");
      const adminReturnReason=$("adminApprovedReturnReason");
      const returnToCollaboratorBtn=$("returnClosingToCollaboratorBtn");
      const returnToManagerBtn=$("returnClosingToManagerBtn");
      const adminReturnStatus=$("adminApprovedReturnStatus");
      const adminReturnHelp=$("adminApprovedReturnHelp");

      if(adminReturnPanel)adminReturnPanel.hidden=!isAdmin();
      if(adminReturnReason){
        adminReturnReason.disabled=!approvedForAdministrativeReturn;
      }
      if(returnToCollaboratorBtn){
        returnToCollaboratorBtn.disabled=!approvedForAdministrativeReturn;
      }
      if(returnToManagerBtn){
        returnToManagerBtn.disabled=!approvedForAdministrativeReturn;
      }
      if(adminReturnStatus){
        adminReturnStatus.textContent=approvedForAdministrativeReturn
          ?"Período aprovado selecionado"
          :"Disponível somente após aprovação";
        adminReturnStatus.classList.toggle(
          "ready",
          approvedForAdministrativeReturn
        );
      }
      if(adminReturnHelp){
        adminReturnHelp.textContent=approvedForAdministrativeReturn
          ?"Escolha o destino da devolução e informe obrigatoriamente o motivo."
          :"Selecione um fechamento com situação Aprovado para utilizar esta ação.";
      }
      if(!approvedForAdministrativeReturn&&adminReturnReason){
        adminReturnReason.value="";
      }
    }catch(error){
      handleError(
        error,
        "Não foi possível calcular o planejado do fechamento."
      );
    }
  }
  $("loadClosingBtn").onclick=loadClosing;
  $("closingUser").onchange=loadClosing;
  $("closingMonth").onchange=loadClosing;

  function switchClosingView(view, shouldRender=true){
    const selected=view==="history"?"history":"current";

    document.querySelectorAll("[data-closing-view]").forEach(button=>{
      const active=button.dataset.closingView===selected;
      button.classList.toggle("active",active);
      button.setAttribute("aria-selected",String(active));
    });

    if($("currentClosingPanel")) $("currentClosingPanel").hidden=selected!=="current";
    if($("closingHistoryPanel")) $("closingHistoryPanel").hidden=selected!=="history";

    try{sessionStorage.setItem("aponta-horas-closing-view",selected)}catch(_){}

    if(!shouldRender)return;
    if(selected==="history") renderClosingHistory();
    else loadClosing();
  }

  async function renderActiveClosingView(){
    const active=document.querySelector("[data-closing-view].active")?.dataset.closingView||"current";
    if(active==="history") await renderClosingHistory();
    else await loadClosing();
  }

  function closingHistoryKey(userId,monthRef){
    return `${userId}|${String(monthRef||"").slice(0,7)}`;
  }
  /* APONTA P3 v2.19.12 — planejado x apontado no fechamento */
  function profileDailyHours(userId){
    const value=Number(
      profiles.find(profile=>profile.id===userId)?.daily_hours||8
    );
    return Number.isFinite(value)&&value>0?value:8;
  }

  async function loadApprovedAbsencesForPeriod(startDate,endDate,userId=""){
    let query=sb
      .from("absences")
      .select("user_id,start_date,end_date,absence_type,approval_status")
      .lte("start_date",endDate)
      .gte("end_date",startDate)
      .eq("approval_status","aprovado");

    if(userId)query=query.eq("user_id",userId);

    const {data,error}=await query;
    if(error)throw error;
    return data||[];
  }

  function plannedHoursSummary(userId,monthRef,approvedAbsences=[]){
    const month=String(monthRef||"").slice(0,7);
    const start=firstDay(month);
    const end=lastDay(month);
    const dailyHours=profileDailyHours(userId);
    const holidayDates=new Set(
      holidays.map(row=>String(row.holiday_date||"").slice(0,10))
    );
    const userAbsences=approvedAbsences.filter(row=>
      row.user_id===userId&&
      row.start_date<=end&&
      row.end_date>=start
    );

    let grossWorkDays=0;
    let holidayWorkDays=0;
    let absenceWorkDays=0;
    let plannedWorkDays=0;

    const cursor=new Date(`${start}T12:00:00Z`);
    const finalDate=new Date(`${end}T12:00:00Z`);

    while(cursor<=finalDate){
      const date=cursor.toISOString().slice(0,10);
      const dayOfWeek=cursor.getUTCDay();

      if(dayOfWeek!==0&&dayOfWeek!==6){
        grossWorkDays+=1;

        if(holidayDates.has(date)){
          holidayWorkDays+=1;
        }else if(userAbsences.some(row=>
          row.start_date<=date&&row.end_date>=date
        )){
          absenceWorkDays+=1;
        }else{
          plannedWorkDays+=1;
        }
      }

      cursor.setUTCDate(cursor.getUTCDate()+1);
    }

    return {
      daily_hours:dailyHours,
      gross_work_days:grossWorkDays,
      holiday_work_days:holidayWorkDays,
      absence_work_days:absenceWorkDays,
      planned_work_days:plannedWorkDays,
      planned_hours:plannedWorkDays*dailyHours
    };
  }

  function closingBalance(pointedHours,plannedHours){
    return Number(pointedHours||0)-Number(plannedHours||0);
  }

  function signedHours(value){
    const number=Number(value||0);
    if(Math.abs(number)<0.005)return "0,00";
    return `${number>0?"+":""}${fmt(number)}`;
  }

  function closingConference(balance){
    const difference=Number(balance||0);

    if(Math.abs(difference)<0.01){
      return {
        key:"complete",
        label:"Completo",
        detail:"Apontado igual ao planejado"
      };
    }

    if(difference<0){
      return {
        key:"missing",
        label:`Faltam ${fmt(Math.abs(difference))} h`,
        detail:"Apontamento abaixo do planejado"
      };
    }

    return {
      key:"excess",
      label:`Excedente ${fmt(difference)} h`,
      detail:"Apontamento acima do planejado"
    };
  }

  function plannedHoursDetail(summary){
    return (
      `${summary.gross_work_days} dia${summary.gross_work_days===1?"":"s"} útil${summary.gross_work_days===1?"":"eis"} bruto${summary.gross_work_days===1?"":"s"} `+
      `− ${summary.holiday_work_days} feriado${summary.holiday_work_days===1?"":"s"} `+
      `− ${summary.absence_work_days} dia${summary.absence_work_days===1?"":"s"} de ausência aprovada `+
      `= ${summary.planned_work_days} dia${summary.planned_work_days===1?"":"s"} planejado${summary.planned_work_days===1?"":"s"} `+
      `× ${fmt(summary.daily_hours)} h/dia`
    );
  }



  function updateClosingHistoryBulkActions(){
    const count=selectedClosingHistoryIds.size;
    const countElement=$("selectedClosingsCount");
    const clearButton=$("clearSelectedClosingsBtn");
    const approveButton=$("approveSelectedClosingsBtn");
    const returnButton=$("returnSelectedClosingsBtn");
    const selectAll=$("selectAllVisibleClosings");

    if(countElement){
      countElement.textContent=`${count} selecionado${count===1?"":"s"}`;
    }

    if(clearButton)clearButton.disabled=count===0;
    if(approveButton)approveButton.disabled=count===0;
    if(returnButton)returnButton.disabled=count===0;

    if(selectAll){
      const selectedVisible=visibleReviewableClosingIds.filter(
        id=>selectedClosingHistoryIds.has(id)
      ).length;

      selectAll.checked=
        visibleReviewableClosingIds.length>0&&
        selectedVisible===visibleReviewableClosingIds.length;
      selectAll.indeterminate=
        selectedVisible>0&&
        selectedVisible<visibleReviewableClosingIds.length;
      selectAll.disabled=visibleReviewableClosingIds.length===0;
    }
  }

  function clearClosingHistorySelection(){
    selectedClosingHistoryIds.clear();
    document.querySelectorAll("[data-select-closing]").forEach(input=>{
      input.checked=false;
    });
    updateClosingHistoryBulkActions();
  }

  function updateClosingHistorySummary(rows){
    const totalPlanned=rows.reduce(
      (sum,row)=>sum+Number(row.planned_hours||0),
      0
    );
    const totalPointed=rows.reduce(
      (sum,row)=>sum+Number(row.total_hours||0),
      0
    );
    const pending=rows.filter(row=>row.status==="enviado").length;
    const approved=rows.filter(row=>row.status==="aprovado").length;

    if($("closingHistoryTotal")){
      $("closingHistoryTotal").textContent=String(rows.length);
    }
    if($("closingHistoryPlannedHours")){
      $("closingHistoryPlannedHours").textContent=fmt(totalPlanned);
    }
    if($("closingHistoryHours")){
      $("closingHistoryHours").textContent=fmt(totalPointed);
    }
    if($("closingHistoryPending")){
      $("closingHistoryPending").textContent=String(pending);
    }
    if($("closingHistoryApproved")){
      $("closingHistoryApproved").textContent=String(approved);
    }
    if($("closingHistoryCountBadge")){
      $("closingHistoryCountBadge").textContent=
        `${rows.length} registro${rows.length===1?"":"s"}`;
    }
  }
  async function renderClosingHistory(){
    const table=$("closingHistoryTable");
    if(!table)return;

    const startMonth=
      $("closingHistoryStartMonth")?.value||
      `${monthNow().slice(0,4)}-01`;
    const endMonth=
      $("closingHistoryEndMonth")?.value||
      monthNow();
    const selectedUser=
      isManager()
        ?($("closingHistoryUser")?.value||"")
        :me.id;
    const selectedStatus=
      $("closingHistoryStatus")?.value||"";
    const selectedProject=
      $("closingHistoryProject")?.value||"";
    const search=
      normalizeText($("closingHistorySearch")?.value||"");

    if(endMonth<startMonth){
      toast(
        "O mês final não pode ser anterior ao mês inicial.",
        true
      );
      return;
    }

    const columnCount=isManager()?13:12;
    table.innerHTML=
      `<tr><td colspan="${columnCount}" class="empty">`+
      `Carregando fechamentos e horas planejadas...</td></tr>`;

    try{
      let query=sb
        .from("monthly_closings")
        .select("*")
        .gte("month_ref",firstDay(startMonth))
        .lte("month_ref",firstDay(endMonth))
        .in("status",["enviado","aprovado","devolvido"])
        .order("month_ref",{ascending:false})
        .order("submitted_at",{ascending:false});

      if(selectedUser)query=query.eq("user_id",selectedUser);
      if(selectedStatus)query=query.eq("status",selectedStatus);
      if(!isManager())query=query.eq("user_id",me.id);

      const [{data:closings,error},entries,approvedAbsences]=
        await Promise.all([
          query,
          selectEntries(
            firstDay(startMonth),
            lastDay(endMonth),
            selectedUser||"",
            ""
          ),
          loadApprovedAbsencesForPeriod(
            firstDay(startMonth),
            lastDay(endMonth),
            selectedUser||""
          )
        ]);

      if(error)throw error;

      const aggregate=new Map();

      entries.forEach(entry=>{
        const key=closingHistoryKey(
          entry.user_id,
          entry.entry_date
        );

        if(!aggregate.has(key)){
          aggregate.set(
            key,
            {hours:0,projectIds:new Set()}
          );
        }

        const item=aggregate.get(key);
        item.hours+=Number(entry.hours||0);

        if(entry.project_id){
          item.projectIds.add(entry.project_id);
        }
      });

      let rows=(closings||[]).map(closing=>{
        const item=
          aggregate.get(
            closingHistoryKey(
              closing.user_id,
              closing.month_ref
            )
          )||
          {hours:0,projectIds:new Set()};

        const projectIds=[...item.projectIds];
        const planned=plannedHoursSummary(
          closing.user_id,
          closing.month_ref,
          approvedAbsences
        );
        const balance=closingBalance(
          item.hours,
          planned.planned_hours
        );
        const conference=closingConference(balance);

        return {
          ...closing,
          total_hours:item.hours,
          ...planned,
          balance_hours:balance,
          conference_key:conference.key,
          conference_label:conference.label,
          conference_detail:conference.detail,
          planned_detail:plannedHoursDetail(planned),
          project_ids:projectIds,
          project_names:projectIds
            .map(projectName)
            .filter(name=>name&&name!=="—")
        };
      });

      if(selectedProject){
        rows=rows.filter(
          row=>row.project_ids.includes(selectedProject)
        );
      }

      if(search){
        rows=rows.filter(row=>
          normalizeText([
            profileName(row.user_id),
            row.project_names.join(" "),
            statusLabel(row.status),
            profileName(row.reviewed_by),
            row.review_note,
            row.conference_label,
            row.planned_detail
          ].join(" ")).includes(search)
        );
      }

      closingHistoryRows=rows;
      visibleReviewableClosingIds=
        isManager()
          ?rows
            .filter(row=>row.status==="enviado")
            .map(row=>row.id)
          :[];

      const visibleReviewableSet=
        new Set(visibleReviewableClosingIds);

      Array.from(selectedClosingHistoryIds).forEach(id=>{
        if(!visibleReviewableSet.has(id)){
          selectedClosingHistoryIds.delete(id);
        }
      });

      updateClosingHistorySummary(rows);
      updateClosingHistoryBulkActions();

      table.innerHTML=rows.map(row=>{
        const projectsText=row.project_names.length
          ?row.project_names.join(", ")
          :"Sem projeto identificado";
        const canReview=
          isManager()&&row.status==="enviado";

        const selectorCell=isManager()
          ?`<td data-label="Selecionar">${
              canReview
                ?`<input class="closing-history-row-selector" `+
                  `type="checkbox" data-select-closing="${row.id}" `+
                  `${selectedClosingHistoryIds.has(row.id)?"checked":""} `+
                  `aria-label="Selecionar fechamento de `+
                  `${esc(profileName(row.user_id))}, `+
                  `${esc(monthLabel(row.month_ref))}">`
                :`<span class="closing-history-not-reviewable" `+
                  `title="Somente fechamentos enviados podem ser analisados em lote">—</span>`
            }</td>`
          :"";

        return `<tr class="closing-workload-row closing-${row.conference_key}">
          ${selectorCell}
          <td data-label="Colaborador">
            <strong>${esc(profileName(row.user_id))}</strong>
            <small class="closing-daily-hours">
              Jornada: ${fmt(row.daily_hours)} h/dia
            </small>
          </td>
          <td data-label="Mês">
            <strong>${esc(monthLabel(row.month_ref))}</strong>
          </td>
          <td data-label="Planejado" title="${esc(row.planned_detail)}">
            <strong>${fmt(row.planned_hours)}</strong>
            <small>${row.planned_work_days} dias</small>
          </td>
          <td data-label="Apontado">
            <strong>${fmt(row.total_hours)}</strong>
          </td>
          <td data-label="Saldo">
            <strong class="closing-balance-${row.conference_key}">
              ${signedHours(row.balance_hours)}
            </strong>
          </td>
          <td data-label="Conferência">
            <span
              class="badge closing-conference closing-conference-${row.conference_key}"
              title="${esc(row.conference_detail)}">
              ${esc(row.conference_label)}
            </span>
          </td>
          <td data-label="Projetos">
            <span
              class="closing-projects"
              title="${esc(projectsText)}">
              ${esc(projectsText)}
            </span>
          </td>
          <td data-label="Enviado em">
            ${dateTimeBR(row.submitted_at)}
          </td>
          <td data-label="Situação">
            <span class="badge status-${esc(row.status)}">
              ${esc(statusLabel(row.status))}
            </span>
          </td>
          <td data-label="Revisado por">
            ${row.reviewed_by
              ?esc(profileName(row.reviewed_by))
              :"—"}
          </td>
          <td data-label="Observação">
            ${esc(row.review_note||"—")}
          </td>
          <td data-label="Ações">
            <div class="table-actions">
              <button
                class="btn secondary small"
                type="button"
                data-open-closing="${row.id}">
                Abrir
              </button>
            </div>
          </td>
        </tr>`;
      }).join("")||
        `<tr><td colspan="${columnCount}" class="empty">`+
        `Nenhum fechamento enviado encontrado com os filtros selecionados.`+
        `</td></tr>`;
    }catch(error){
      closingHistoryRows=[];
      visibleReviewableClosingIds=[];
      clearClosingHistorySelection();
      updateClosingHistorySummary([]);

      table.innerHTML=
        `<tr><td colspan="${columnCount}" class="empty">`+
        `Não foi possível carregar os fechamentos e o planejado.`+
        `</td></tr>`;

      handleError(
        error,
        "Não foi possível consultar o planejado. Confira se férias e afastamentos estão instalados no banco."
      );
    }
  }
  document.querySelectorAll("[data-closing-view]").forEach(button=>{
    button.addEventListener("click",()=>switchClosingView(button.dataset.closingView));
  });

  try{
    switchClosingView(sessionStorage.getItem("aponta-horas-closing-view")||"current",false);
  }catch(_){
    switchClosingView("current",false);
  }

  if($("filterClosingHistoryBtn")) $("filterClosingHistoryBtn").onclick=()=>{
    clearClosingHistorySelection();
    renderClosingHistory();
  };
  if($("closingHistorySearch")){
    $("closingHistorySearch").addEventListener("keydown",event=>{
      if(event.key==="Enter"){
        clearClosingHistorySelection();
        renderClosingHistory();
      }
    });
  }

  if($("clearClosingHistoryFiltersBtn")){
    $("clearClosingHistoryFiltersBtn").onclick=()=>{
      $("closingHistorySearch").value="";
      if(isManager()) $("closingHistoryUser").value="";
      $("closingHistoryStartMonth").value=`${monthNow().slice(0,4)}-01`;
      $("closingHistoryEndMonth").value=monthNow();
      $("closingHistoryStatus").value="";
      $("closingHistoryProject").value="";
      clearClosingHistorySelection();
      renderClosingHistory();
    };
  }

  if($("exportClosingHistoryBtn")){
    $("exportClosingHistoryBtn").onclick=()=>{
      if(!closingHistoryRows.length){
        toast(
          "Não há fechamentos filtrados para exportar.",
          true
        );
        return;
      }

      downloadCsv(
        `fechamentos_enviados_${today()}.csv`,
        [
          [
            "Colaborador",
            "Mês",
            "Jornada diária",
            "Dias úteis brutos",
            "Feriados úteis descontados",
            "Dias de ausência aprovados descontados",
            "Dias planejados",
            "Horas planejadas",
            "Horas apontadas",
            "Saldo",
            "Conferência",
            "Projetos",
            "Enviado em",
            "Situação",
            "Revisado por",
            "Revisado em",
            "Observação"
          ],
          ...closingHistoryRows.map(row=>[
            profileName(row.user_id),
            monthLabel(row.month_ref),
            fmt(row.daily_hours),
            row.gross_work_days,
            row.holiday_work_days,
            row.absence_work_days,
            row.planned_work_days,
            fmt(row.planned_hours),
            fmt(row.total_hours),
            signedHours(row.balance_hours),
            row.conference_label,
            row.project_names.join(", "),
            dateTimeBR(row.submitted_at),
            statusLabel(row.status),
            row.reviewed_by
              ?profileName(row.reviewed_by)
              :"",
            dateTimeBR(row.reviewed_at),
            row.review_note||""
          ])
        ]
      );
    };
  }
  if($("selectAllVisibleClosings")){
    $("selectAllVisibleClosings").onchange=event=>{
      visibleReviewableClosingIds.forEach(id=>{
        if(event.target.checked)selectedClosingHistoryIds.add(id);
        else selectedClosingHistoryIds.delete(id);
      });

      document.querySelectorAll("[data-select-closing]").forEach(input=>{
        input.checked=event.target.checked;
      });

      updateClosingHistoryBulkActions();
    };
  }

  if($("clearSelectedClosingsBtn")){
    $("clearSelectedClosingsBtn").onclick=clearClosingHistorySelection;
  }

  async function reviewSelectedClosings(status){
    if(!isManager()){
      toast("Somente Gestor ou Administrador pode analisar fechamentos.",true);
      return;
    }

    const ids=Array.from(selectedClosingHistoryIds);
    if(!ids.length){
      toast("Selecione pelo menos um fechamento enviado.",true);
      return;
    }

    const note=$("closingHistoryBulkNote")?.value.trim()||"";
    if(status==="devolvido"&&!note){
      toast("Informe o motivo da devolução em lote.",true);
      $("closingHistoryBulkNote")?.focus();
      return;
    }

    const actionLabel=status==="aprovado"?"aprovar":"devolver";
    const confirmed=window.confirm(
      `${actionLabel.charAt(0).toUpperCase()+actionLabel.slice(1)} `+
      `${ids.length} fechamento${ids.length===1?"":"s"} selecionado${ids.length===1?"":"s"}?

`+
      (status==="aprovado"
        ?"Os apontamentos dos períodos serão marcados como Aprovados."
        :"Os apontamentos dos períodos serão devolvidos aos colaboradores para correção.")
    );

    if(!confirmed)return;

    showLoading(true);
    try{
      const {data,error}=await sb.rpc(
        "aponta_review_monthly_closings_bulk_v2190",
        {
          p_closing_ids:ids,
          p_status:status,
          p_review_note:note
        }
      );

      if(error)throw error;

      const processed=Number(data?.closings_processed||0);
      const entries=Number(data?.entries_updated||0);
      const skipped=Number(data?.closings_skipped||0);

      clearClosingHistorySelection();
      if($("closingHistoryBulkNote"))$("closingHistoryBulkNote").value="";

      await Promise.all([
        renderClosingHistory(),
        loadClosing(),
        renderEntries(),
        renderDashboard()
      ]);

      const actionDone=status==="aprovado"?"aprovado":"devolvido";
      toast(
        `${processed} fechamento${processed===1?"":"s"} ${actionDone}${processed===1?"":"s"}. `+
        `${entries} apontamento${entries===1?"":"s"} atualizado${entries===1?"":"s"}.`+
        (skipped?` ${skipped} item${skipped===1?"":"s"} ignorado${skipped===1?"":"s"} por não estar enviado.`:"")
      );
    }catch(error){
      handleError(
        error,
        "Não foi possível analisar os fechamentos selecionados. Execute o SQL obrigatório da versão 2.19.0 no Supabase."
      );
    }finally{
      showLoading(false);
    }
  }

  if($("approveSelectedClosingsBtn")){
    $("approveSelectedClosingsBtn").onclick=()=>reviewSelectedClosings("aprovado");
  }

  if($("returnSelectedClosingsBtn")){
    $("returnSelectedClosingsBtn").onclick=()=>reviewSelectedClosings("devolvido");
  }

  if($("closingHistoryTable")){
    $("closingHistoryTable").onchange=event=>{
      const selector=event.target.closest("[data-select-closing]");
      if(!selector)return;

      const id=selector.dataset.selectClosing;
      if(selector.checked)selectedClosingHistoryIds.add(id);
      else selectedClosingHistoryIds.delete(id);
      updateClosingHistoryBulkActions();
    };

    $("closingHistoryTable").onclick=async event=>{
      const button=event.target.closest("[data-open-closing]");
      if(!button)return;
      const row=closingHistoryRows.find(item=>item.id===button.dataset.openClosing);
      if(!row)return;

      if(isManager()) $("closingUser").value=row.user_id;
      $("closingMonth").value=String(row.month_ref).slice(0,7);
      switchClosingView("current",false);
      await loadClosing();
      $("currentClosingPanel")?.scrollIntoView({behavior:"smooth",block:"start"});
    };
  }

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

      await Promise.all([loadClosing(),renderEntries(),renderDashboard(),renderClosingHistory()]);

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
      await Promise.all([loadClosing(),renderEntries(),renderDashboard(),renderClosingHistory()]);
    }catch(e){handleError(e)}finally{showLoading(false)}
  }
  $("approveClosingBtn").onclick=()=>reviewClosing("aprovado");
  $("rejectClosingBtn").onclick=()=>reviewClosing("devolvido");

  async function returnApprovedClosing(destination){
    if(!isAdmin()){
      toast("Somente o Administrador pode devolver um período depois da aprovação.",true);
      return;
    }

    if(!currentClosing||currentClosing.status!=="aprovado"){
      toast("Selecione um fechamento aprovado.",true);
      return;
    }

    const reason=$("adminApprovedReturnReason").value.trim();
    if(!reason){
      toast("Informe o motivo da devolução.",true);
      $("adminApprovedReturnReason").focus();
      return;
    }

    const toCollaborator=destination==="colaborador";
    const destinationLabel=toCollaborator
      ?"ao colaborador para correção"
      :"à fila de aprovação do gestor";

    const confirmed=window.confirm(
      `Devolver este período ${destinationLabel}?\n\n`+
      (toCollaborator
        ?"Os apontamentos serão liberados para edição e exclusão."
        :"Os apontamentos continuarão bloqueados para o colaborador.")
    );

    if(!confirmed)return;

    showLoading(true);

    try{
      const {data,error}=await sb.rpc(
        "aponta_admin_return_approved_closing_v2176",
        {
          p_closing_id:currentClosing.id,
          p_destination:destination,
          p_reason:reason
        }
      );

      if(error)throw error;

      $("adminApprovedReturnReason").value="";

      await Promise.all([
        loadClosing(),
        renderEntries(),
        renderDashboard(),
        renderClosingHistory()
      ]);

      if(toCollaborator){
        toast(
          `${data?.entries_updated??0} apontamento${Number(data?.entries_updated||0)===1?"":"s"} `+
          "devolvido(s) ao colaborador para correção."
        );
      }else{
        toast(
          "O fechamento voltou para a fila de aprovação do gestor."
        );
      }
    }catch(error){
      handleError(
        error,
        "Não foi possível devolver o período. Execute o SQL obrigatório da versão 2.17.6 no Supabase."
      );
    }finally{
      showLoading(false);
    }
  }

  $("returnClosingToCollaboratorBtn").onclick=()=>returnApprovedClosing("colaborador");
  $("returnClosingToManagerBtn").onclick=()=>returnApprovedClosing("gestor");

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
      const reportHours=lastReportRows.reduce(
        (sum,row)=>sum+Number(row.hours||0),
        0
      );
      const reportPeople=new Set(
        lastReportRows.map(row=>row.user_id).filter(Boolean)
      ).size;

      $("reportTotal").textContent=
        `${fmt(reportHours)} horas · `+
        `${lastReportRows.length} apontamento${lastReportRows.length===1?"":"s"} · `+
        `${reportPeople} colaborador${reportPeople===1?"":"es"}`;
      $("reportTable").innerHTML=lastReportRows.map(x=>`<tr><td>${dateBR(x.entry_date)}</td><td>${esc(profileName(x.user_id))}</td><td>${esc(projectName(x.project_id))}</td><td>${esc(areaName(x.area_code))}</td><td>${esc(entryReferenceName(x))}</td><td>${esc(activityName(x.activity_id))}</td><td>${fmt(x.hours)}</td><td>${esc(x.details)}</td><td><span class="badge status-${x.status}">${statusLabel(x.status)}</span></td></tr>`).join("")||'<tr><td colspan="9" class="empty">Sem dados</td></tr>';
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


  function switchCatalogView(view){
    const allowed=new Set(["general","references","projects","holidays"]);
    const selectedView=allowed.has(view)?view:"general";
    const previousView=document.querySelector("[data-catalog-view].active")?.dataset.catalogView||"";
    if(previousView==="projects"&&selectedView!=="projects"){
      resetProjectStructureSelection();
    }

    document.querySelectorAll("[data-catalog-view]").forEach(button=>{
      const isActive=button.dataset.catalogView===selectedView;
      button.classList.toggle("active",isActive);
      button.setAttribute("aria-selected",String(isActive));
    });

    const panelMap={
      general:"generalCatalogPanel",
      references:"referenceCatalogPanel",
      projects:"projectStructureCatalogPanel",
      holidays:"holidayCatalogPanel"
    };

    Object.entries(panelMap).forEach(([key,id])=>{
      const panel=$(id);
      if (panel) panel.hidden=key!==selectedView;
    });

    try{
      sessionStorage.setItem("aponta-p3-catalog-view",selectedView);
    }catch(_){}
  }

  document.querySelectorAll("[data-catalog-view]").forEach(button=>{
    button.addEventListener("click",()=>{
      switchCatalogView(button.dataset.catalogView);
    });
  });

  try{
    switchCatalogView(
      sessionStorage.getItem("aponta-p3-catalog-view")||"general"
    );
  }catch(_){
    switchCatalogView("general");
  }

  async function renderActiveReport(){
    const active=document.querySelector("[data-report-view].active")?.dataset.reportView||"projects";
    if(active==="people") await renderPeopleReport();
    else await renderReport();
  }

  function switchReportView(view){
    const selected=view==="people"?"people":"projects";
    document.querySelectorAll("[data-report-view]").forEach(button=>{
      const active=button.dataset.reportView===selected;
      button.classList.toggle("active",active);
      button.setAttribute("aria-selected",String(active));
    });
    $("projectReportPanel").hidden=selected!=="projects";
    $("peopleReportPanel").hidden=selected!=="people";
    try{sessionStorage.setItem("aponta-p3-report-view",selected)}catch(_){}
    if(selected==="people") renderPeopleReport();
    else renderReport();
  }

  document.querySelectorAll("[data-report-view]").forEach(button=>{
    button.addEventListener("click",()=>switchReportView(button.dataset.reportView));
  });

  try{switchReportView(sessionStorage.getItem("aponta-p3-report-view")||"projects")}catch(_){switchReportView("projects")}

  $("selectAllActivityAreasBtn").onclick=()=>setAllActivityAreas("activityAreasCheckboxes",true);
  $("clearActivityAreasBtn").onclick=()=>setAllActivityAreas("activityAreasCheckboxes",false);
  $("selectAllEditActivityAreasBtn").onclick=()=>setAllActivityAreas("editActivityAreasCheckboxes",true);
  $("clearEditActivityAreasBtn").onclick=()=>setAllActivityAreas("editActivityAreasCheckboxes",false);

  $("generateReportBtn").onclick=renderReport;
  $("generatePeopleReportBtn").onclick=renderPeopleReport;

  $("exportReportBtn").onclick=()=>{
    const lines=[["Data","Colaborador","Projeto","Área","Referência","Atividade","Horas","Observação","Status"],...lastReportRows.map(x=>[x.entry_date,profileName(x.user_id),projectName(x.project_id),areaName(x.area_code),entryReferenceName(x),activityName(x.activity_id),String(x.hours).replace(".",","),x.details,statusLabel(x.status)])];
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

  $("projectForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("projects").insert({code:$("projectCode").value.trim()||null,client_name:$("projectClient").value.trim(),name:$("projectName").value.trim(),description:$("projectDescription").value.trim(),created_by:me.id});if(error)handleError(error);else{$("projectForm").reset();toast("Projeto adicionado.");await reloadCatalogs()}};
  $("activityForm").onsubmit=async e=>{
    e.preventDefault();
    const areas=checkedAreaCodes("activityAreasCheckboxes");
    if(!areas.length)return toast("Selecione pelo menos uma área para a atividade.",true);

    showLoading(true);
    try{
      const {data,error}=await sb.rpc(
        "aponta_save_activity_v2180",
        {
          p_activity_id:null,
          p_code:normalizeActivityCode($("activityCode").value)||null,
          p_name:$("activityName").value.trim(),
          p_discipline_name:$("activityDiscipline").value.trim(),
          p_nature:$("activityNature").value.trim(),
          p_usage_description:$("activityUsageDescription").value.trim(),
          p_observation_requirement:normalizeObservationRequirement(
            $("activityObservationRequirement").value
          ),
          p_active:true,
          p_areas:areas
        }
      );

      if(error)throw error;
      if(!data?.id)throw new Error("O banco não confirmou a atividade criada.");

      const confirmedAreas=applyConfirmedActivityAreas(
        data.id,
        Array.isArray(data.areas)?data.areas:areas
      );

      $("activityForm").reset();
      $("activityObservationRequirement").value="Opcional";
      renderActivityAreaCheckboxes("activityAreasCheckboxes");

      await reloadCatalogs();

      // A resposta da RPC é a confirmação transacional do banco.
      // Reaplica localmente para evitar leitura antiga imediatamente após o insert.
      applyConfirmedActivityAreas(data.id,confirmedAreas);
      renderActivitiesCatalog();

      toast(
        `Atividade adicionada com ${confirmedAreas.length} `+
        `área${confirmedAreas.length===1?"":"s"}.`
      );
    }catch(error){
      handleError(
        error,
        "Não foi possível salvar a atividade. Execute o SQL obrigatório da versão 2.18.3."
      );
    }finally{
      showLoading(false);
    }
  };
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

  function safeStructureCode(value,fallback="ITEM"){
    const normalized=String(value||fallback).normalize("NFD").replace(/[\u0300-\u036f]/g,"").toUpperCase().replace(/[^A-Z0-9]+/g,"-").replace(/^-+|-+$/g,"");
    return normalized||fallback;
  }

  function compactCatalogKey(value){return normalizeText(value).replace(/[^a-z0-9]/g,"");}
  function standardRoomDefinitionFor(room){if(!room)return null;const code=compactCatalogKey(room.code),name=compactCatalogKey(room.name);return STANDARD_PROJECT_ROOMS.find(def=>def.aliases.includes(code)||def.aliases.includes(name))||null;}
  function instanceModuleCount(instanceId){return projectRoomInstanceModules.filter(row=>row.room_instance_id===instanceId&&row.active).length;}
  function roomCatalogName(roomId){return rooms.find(row=>row.id===roomId)?.name||"Sala";}
  function roomCatalogCode(roomId){return rooms.find(row=>row.id===roomId)?.code||"SALA";}

  async function syncRoomInstanceModuleQuantity(instanceId,desiredValue){
    const desired=Number(desiredValue);if(!Number.isInteger(desired)||desired<1)throw new Error("A quantidade de módulos deve ser um número inteiro maior que zero.");
    const instance=projectRoomInstances.find(row=>row.id===instanceId);if(!instance)throw new Error("Sala específica não encontrada.");
    const def=standardRoomDefinitionFor(rooms.find(row=>row.id===instance.room_id));if(def?.monoblock&&desired>MAX_MONOBLOCK_MODULES)throw new Error(`O MONOBLOCO permite no máximo ${MAX_MONOBLOCK_MODULES} módulos.`);
    let rows=projectRoomInstanceModules.filter(row=>row.room_instance_id===instanceId).sort((a,b)=>(a.module_number||0)-(b.module_number||0));
    const active=rows.filter(row=>row.active),inactive=rows.filter(row=>!row.active);
    while(active.length<desired&&inactive.length){const row=inactive.shift();const changes={active:true,updated_at:new Date().toISOString()};if(def?.monoblock){changes.has_lower_part=false;changes.has_upper_part=false;}const{error}=await sb.from("project_room_instance_modules").update(changes).eq("id",row.id);if(error)throw error;row.active=true;if(def?.monoblock){row.has_lower_part=false;row.has_upper_part=false;}active.push(row);}
    let next=Math.max(0,...rows.map(row=>Number(row.module_number||0)))+1;
    while(active.length<desired){const number=next++;const code=`${safeStructureCode(instance.code||instance.display_name,"SALA")}-M${String(number).padStart(2,"0")}`;const display=`Módulo ${String(number).padStart(2,"0")}`;const hasParts=!def?.monoblock;const{data,error}=await sb.from("project_room_instance_modules").insert({room_instance_id:instanceId,module_number:number,code,display_name:display,order_index:number,has_lower_part:hasParts,has_upper_part:hasParts,active:true}).select("*").single();if(error)throw error;projectRoomInstanceModules.push(data);active.push(data);}
    if(active.length>desired){for(const row of active.slice(desired)){const{error}=await sb.from("project_room_instance_modules").update({active:false,updated_at:new Date().toISOString()}).eq("id",row.id);if(error)throw error;row.active=false;}}
  }


  function resetProjectStructureSelection(){
    const composition=$("projectCompositionProject");
    const moduleProject=$("projectRoomModuleProject");
    const moduleRoom=$("projectRoomModuleRoom");
    const roomCatalog=$("projectRoomInstanceRoom");

    if(composition)composition.value="";
    if(moduleProject)moduleProject.value="";
    if(roomCatalog)roomCatalog.value="";

    if(moduleRoom){
      moduleRoom.innerHTML='<option value="">Selecione primeiro o projeto</option>';
      moduleRoom.value="";
      moduleRoom.disabled=true;
    }

    if($("projectRoomInstanceCount"))$("projectRoomInstanceCount").value="1";
    if($("projectRoomInstanceModuleCount"))$("projectRoomInstanceModuleCount").value="1";
    if($("projectRoomInstanceNamePrefix"))$("projectRoomInstanceNamePrefix").value="";

    selectedProjectRoomIds.clear();
    renderProjectComposition();
    renderProjectStructureTables();
  }

  function renderProjectComposition(){
    const projectId=$("projectCompositionProject")?.value;const status=$("projectCompositionStatus");
    const count=projectRoomInstances.filter(row=>row.project_id===projectId&&row.active).length;
    if(status)status.innerHTML=projectId?`<strong>${esc(projectName(projectId))}</strong><span>${count} sala${count===1?"":"s"} cadastrada${count===1?"":"s"}</span>`:"Selecione um projeto para configurar.";
  }

  const selectedProjectRoomIds=new Set();

  function visibleProjectRoomIds(){
    return Array.from(document.querySelectorAll('#projectRoomsTable [data-select-room-instance]')).map(input=>input.dataset.selectRoomInstance);
  }

  function updateProjectRoomBulkActions(){
    const visible=visibleProjectRoomIds();
    const selectedVisible=visible.filter(id=>selectedProjectRoomIds.has(id));
    const count=$('selectedProjectRoomsCount');
    if(count)count.textContent=`${selectedProjectRoomIds.size} selecionada${selectedProjectRoomIds.size===1?'':'s'}`;
    const all=$('selectAllProjectRooms');
    if(all){
      all.checked=visible.length>0&&selectedVisible.length===visible.length;
      all.indeterminate=selectedVisible.length>0&&selectedVisible.length<visible.length;
    }
    ['clearSelectedProjectRoomsBtn','inactivateSelectedProjectRoomsBtn','deleteSelectedProjectRoomsBtn'].forEach(id=>{
      const button=$(id);if(button)button.disabled=selectedProjectRoomIds.size===0;
    });
  }

  function renderProjectStructureTables(){
    const projectId=$("projectCompositionProject")?.value||"";

    // A tabela de salas é um cadastro geral e mostra todos os projetos,
    // independentemente do projeto selecionado no formulário superior.
    const allRoomRows=[...projectRoomInstances].sort((a,b)=>{
      const projectComparison=projectName(a.project_id).localeCompare(projectName(b.project_id),"pt-BR");
      if(projectComparison)return projectComparison;

      const roomComparison=roomCatalogCode(a.room_id).localeCompare(roomCatalogCode(b.room_id),"pt-BR");
      if(roomComparison)return roomComparison;

      return (a.order_index||0)-(b.order_index||0)
        ||(a.instance_number||0)-(b.instance_number||0);
    });

    const projectFilter=$("projectRoomsProjectFilter");
    const typeFilter=$("projectRoomsTypeFilter");

    if(projectFilter){
      const previousProject=projectFilter.value;
      const projectIds=[...new Set(
        allRoomRows.map(row=>row.project_id).filter(Boolean)
      )].sort((a,b)=>projectName(a).localeCompare(projectName(b),"pt-BR"));

      projectFilter.innerHTML=
        '<option value="">Todos os projetos</option>'+
        projectIds.map(id=>`<option value="${id}">${esc(projectName(id))}</option>`).join("");

      if(projectIds.includes(previousProject)){
        projectFilter.value=previousProject;
      }
    }

    if(typeFilter){
      const previousType=typeFilter.value;
      const roomIds=[...new Set(
        allRoomRows.map(row=>row.room_id).filter(Boolean)
      )].sort((a,b)=>{
        const codeComparison=roomCatalogCode(a).localeCompare(roomCatalogCode(b),"pt-BR");
        return codeComparison||roomCatalogName(a).localeCompare(roomCatalogName(b),"pt-BR");
      });

      typeFilter.innerHTML=
        '<option value="">Todos os tipos</option>'+
        roomIds.map(id=>`<option value="${id}">${esc(roomCatalogCode(id))} — ${esc(roomCatalogName(id))}</option>`).join("");

      if(roomIds.includes(previousType)){
        typeFilter.value=previousType;
      }
    }

    const searchText=normalizeText($("projectRoomsSearch")?.value||"");
    const selectedProject=$("projectRoomsProjectFilter")?.value||"";
    const selectedType=$("projectRoomsTypeFilter")?.value||"";
    const selectedStatus=$("projectRoomsStatusFilter")?.value||"";

    const roomRows=allRoomRows.filter(row=>{
      if(selectedProject&&row.project_id!==selectedProject)return false;
      if(selectedType&&row.room_id!==selectedType)return false;
      if(selectedStatus==="active"&&!row.active)return false;
      if(selectedStatus==="inactive"&&row.active)return false;

      if(searchText){
        const searchable=normalizeText([
          projectName(row.project_id),
          roomCatalogCode(row.room_id),
          roomCatalogName(row.room_id),
          row.display_name,
          row.instance_number,
          instanceModuleCount(row.id)
        ].join(" "));

        if(!searchable.includes(searchText))return false;
      }

      return true;
    });

    // A área avançada de módulos continua vinculada ao projeto selecionado,
    // para evitar misturar módulos de projetos diferentes.
    const moduleRows=projectId
      ? projectRoomInstanceModules.filter(row=>{
          const instance=projectRoomInstances.find(item=>item.id===row.room_instance_id);
          return instance&&instance.project_id===projectId;
        }).sort((a,b)=>{
          const instanceA=projectRoomInstances.find(item=>item.id===a.room_instance_id);
          const instanceB=projectRoomInstances.find(item=>item.id===b.room_instance_id);
          const roomComparison=roomInstanceName(instanceA?.id).localeCompare(roomInstanceName(instanceB?.id),"pt-BR");
          return roomComparison||(a.order_index||0)-(b.order_index||0);
        })
      : [];

    const activeRoomCount=allRoomRows.filter(row=>row.active).length;
    if($("projectRoomsCount")){
      $("projectRoomsCount").textContent=`${activeRoomCount} sala${activeRoomCount===1?"":"s"}`;
    }

    if($("projectRoomsFilterCount")){
      const total=allRoomRows.length;
      const visible=roomRows.length;
      $("projectRoomsFilterCount").textContent=
        visible===total
          ?`${total} resultado${total===1?"":"s"}`
          :`${visible} de ${total} salas`;
    }

    const existingRoomIds=new Set(projectRoomInstances.map(row=>row.id));
    Array.from(selectedProjectRoomIds).forEach(id=>{
      if(!existingRoomIds.has(id))selectedProjectRoomIds.delete(id);
    });

    $("projectRoomsTable").innerHTML=roomRows.map(row=>`<tr>
      <td><input class="room-instance-selector" type="checkbox" data-select-room-instance="${row.id}" ${selectedProjectRoomIds.has(row.id)?"checked":""} aria-label="Selecionar ${esc(row.display_name||roomCatalogName(row.room_id))}"></td>
      <td>${esc(projectName(row.project_id))}</td>
      <td>${esc(roomCatalogCode(row.room_id))}</td>
      <td>${esc(row.display_name||roomCatalogName(row.room_id))}</td>
      <td>${row.instance_number}</td>
      <td><strong>${instanceModuleCount(row.id)}</strong></td>
      <td><span class="badge">${row.active?"Ativa":"Inativa"}</span></td>
      <td><div class="table-actions">
        <button class="btn primary small" data-edit-room-instance="${row.id}">Editar</button>
        <button class="btn secondary small" data-toggle-room-instance="${row.id}" data-active="${row.active}">${row.active?"Inativar":"Ativar"}</button>
        <button class="btn danger small" data-delete-room-instance="${row.id}">Excluir</button>
      </div></td>
    </tr>`).join("")||(
      allRoomRows.length
        ?'<tr><td colspan="8" class="empty">Nenhuma sala encontrada com os filtros selecionados.</td></tr>'
        :'<tr><td colspan="8" class="empty">Nenhuma sala cadastrada.</td></tr>'
    );

    updateProjectRoomBulkActions();

    if($("projectRoomModulesCount")){
      const activeModuleCount=moduleRows.filter(row=>row.active).length;
      $("projectRoomModulesCount").textContent=`${activeModuleCount} módulo${activeModuleCount===1?"":"s"}`;
    }

    $("projectRoomModulesTable").innerHTML=moduleRows.map(row=>{
      const instance=projectRoomInstances.find(item=>item.id===row.room_instance_id);
      const monoblock=isMonoblockRoomInstance(instance?.id);
      const parts=monoblock
        ?"Não se aplica"
        :([row.has_lower_part?"Inferior":"",row.has_upper_part?"Superior":""].filter(Boolean).join(" + ")||"Nenhuma");

      return `<tr>
        <td>${esc(projectName(instance?.project_id))}</td>
        <td>${esc(roomInstanceName(row.room_instance_id))}</td>
        <td>${esc(row.code)}</td>
        <td>${esc(row.display_name)}</td>
        <td>${esc(parts)}</td>
        <td><span class="badge">${row.active?"Ativo":"Inativo"}</span></td>
        <td><div class="table-actions">
          <button class="btn primary small" data-edit-instance-module="${row.id}">Editar</button>
          <button class="btn secondary small" data-toggle-instance-module="${row.id}" data-active="${row.active}">${row.active?"Inativar":"Ativar"}</button>
          <button class="btn danger small" data-delete-instance-module="${row.id}">Excluir</button>
        </div></td>
      </tr>`;
    }).join("")||(
      projectId
        ?'<tr><td colspan="7" class="empty">Nenhum módulo cadastrado para este projeto</td></tr>'
        :'<tr><td colspan="7" class="empty">Selecione um projeto para visualizar os módulos avançados</td></tr>'
    );
  }

  async function deleteRoomInstance(id){const{error}=await sb.from("project_room_instances").delete().eq("id",id);if(error)throw error;}
  async function deleteRoomInstanceModule(id){const{error}=await sb.from("project_room_instance_modules").delete().eq("id",id);if(error)throw error;}


  function setActivityWorkbookStatus(message,error=false){
    const element=$("activityWorkbookStatus");
    if(!element)return;
    element.textContent=message;
    element.classList.toggle("error",error);
  }

  function updateActivityBulkActions(){
    const count=selectedActivityIds.size;
    const countElement=$("selectedActivitiesCount");
    const selectAll=$("selectAllVisibleActivities");
    const clearButton=$("clearSelectedActivitiesBtn");
    const inactivateButton=$("inactivateSelectedActivitiesBtn");
    const deleteButton=$("deleteSelectedActivitiesBtn");

    if(countElement){
      countElement.textContent=`${count} selecionada${count===1?"":"s"}`;
    }

    [clearButton,inactivateButton,deleteButton].forEach(button=>{
      if(button)button.disabled=count===0;
    });

    if(selectAll){
      const selectedVisible=visibleActivityIds.filter(id=>selectedActivityIds.has(id)).length;
      selectAll.disabled=!isAdmin()||visibleActivityIds.length===0;
      selectAll.checked=visibleActivityIds.length>0&&selectedVisible===visibleActivityIds.length;
      selectAll.indeterminate=selectedVisible>0&&selectedVisible<visibleActivityIds.length;
    }
  }

  function clearActivitySelection(){
    selectedActivityIds.clear();
    document.querySelectorAll("[data-select-activity]").forEach(input=>{
      input.checked=false;
    });
    updateActivityBulkActions();
  }

  function normalizeActivityWorkbookHeader(value){
    return normalizeText(value)
      .replace(/[^a-z0-9]+/g,"_")
      .replace(/^_+|_+$/g,"");
  }

  function activityWorkbookRowMap(row){
    const mapped={};
    Object.entries(row||{}).forEach(([key,value])=>{
      mapped[normalizeActivityWorkbookHeader(key)]=value;
    });
    return mapped;
  }

  function workbookValue(row,aliases){
    for(const alias of aliases){
      const key=normalizeActivityWorkbookHeader(alias);
      if(Object.prototype.hasOwnProperty.call(row,key))return row[key];
    }
    return "";
  }

  function truthySpreadsheetValue(value){
    const normalized=normalizeText(value);
    return ["sim","s","x","1","true","verdadeiro","ativo","ativa"].includes(normalized);
  }

  function parseSpreadsheetObservationRequirement(value,currentValue="Opcional"){
    const normalized=normalizeText(value);
    if(!normalized)return normalizeObservationRequirement(currentValue);

    if([
      "obrigatoria",
      "obrigatorio",
      "sim",
      "s"
    ].includes(normalized)){
      return "Obrigatória";
    }

    if([
      "opcional",
      "nao",
      "n",
      "recomendado",
      "recomendada"
    ].includes(normalized)){
      return "Opcional";
    }

    throw new Error(
      `Observação inválida: "${value}". Use Opcional ou Obrigatória.`
    );
  }

  function parseSpreadsheetActive(value,currentValue=true){
    const normalized=normalizeText(value);
    if(!normalized)return currentValue;
    if(["inativo","inativa","nao","não","n","0","false","falso"].includes(normalized))return false;
    if(["ativo","ativa","sim","s","1","true","verdadeiro"].includes(normalized))return true;
    throw new Error(`Status inválido: "${value}". Use Ativa ou Inativa.`);
  }

  function parseSpreadsheetAreas(row){
    const combined=String(workbookValue(row,[
      "Áreas aplicáveis (códigos)",
      "Areas aplicaveis codigos",
      "Áreas aplicáveis",
      "Areas",
      "Area"
    ])||"").trim();

    const resolved=[];
    const invalid=[];

    const addAreaToken=token=>{
      const clean=String(token||"").trim();
      if(!clean)return;

      const normalized=normalizeText(clean);
      const area=workAreas.find(item=>
        normalizeText(item.code)===normalized||
        normalizeText(item.name)===normalized
      );

      if(area){
        if(!resolved.includes(area.code))resolved.push(area.code);
      }else{
        invalid.push(clean);
      }
    };

    if(combined){
      combined.split(/[;,|\n]+/).forEach(addAreaToken);
    }

    if(!combined){
      workAreas.forEach(area=>{
        const keys=[
          area.code,
          area.name,
          `Área ${area.code}`,
          `Area ${area.code}`
        ];

        const marked=keys.some(key=>
          truthySpreadsheetValue(workbookValue(row,[key]))
        );

        if(marked&&!resolved.includes(area.code))resolved.push(area.code);
      });
    }

    return {codes:resolved,invalid};
  }

  function activityWorkbookRows(){
    return [...activities]
      .sort((a,b)=>
        String(a.code||"").localeCompare(String(b.code||""),"pt-BR")||
        a.name.localeCompare(b.name,"pt-BR")
      )
      .map(activity=>({
        "ID":activity.id,
        "Código":normalizeActivityCode(activity.code),
        "Atividade":activity.name,
        "Disciplina":activity.discipline_name||"",
        "Natureza":activity.nature||"",
        "Áreas aplicáveis (códigos)":activityAreas(activity.id).join("; "),
        "Orientação de uso":activity.usage_description||"",
        "Observação":normalizeObservationRequirement(activity.observation_requirement),
        "Status":activity.active?"Ativa":"Inativa"
      }));
  }

  function downloadActivitiesWorkbook(){
    if(!isAdmin()){
      toast("Somente o Administrador pode baixar a lista de atividades.",true);
      return;
    }

    if(!window.XLSX){
      toast("Biblioteca de Excel não carregada. Atualize a página e tente novamente.",true);
      return;
    }

    const workbook=XLSX.utils.book_new();
    const rows=activityWorkbookRows();
    const activitySheet=XLSX.utils.json_to_sheet(rows,{
      header:[
        "ID",
        "Código",
        "Atividade",
        "Disciplina",
        "Natureza",
        "Áreas aplicáveis (códigos)",
        "Orientação de uso",
        "Observação",
        "Status"
      ]
    });

    activitySheet["!cols"]=[
      {wch:38},
      {wch:16},
      {wch:48},
      {wch:28},
      {wch:22},
      {wch:30},
      {wch:58},
      {wch:14},
      {wch:12}
    ];
    activitySheet["!autofilter"]={ref:`A1:I${Math.max(rows.length+1,2)}`};

    const instructionRows=[
      ["IMPORTAÇÃO DE ATIVIDADES — APONTA P3"],
      [""],
      ["Regra","Orientação"],
      ["ID","Não altere o ID das atividades existentes. Para criar uma nova atividade, deixe o ID vazio."],
      ["Código","Use códigos sem o prefixo EM-. Exemplo: SST-020."],
      ["Atividade","Campo obrigatório e único."],
      ["Áreas aplicáveis (códigos)","Informe um ou mais códigos separados por ponto e vírgula. Exemplo: FAB; MES; MFI."],
      ["Observação","Use Opcional ou Obrigatória."],
      ["Status","Use Ativa ou Inativa."],
      ["Exclusão","Apagar uma linha do Excel não exclui a atividade do sistema. Use a seleção em massa no aplicativo."],
      ["Histórico","Atividades que possuem apontamentos podem ser atualizadas ou inativadas, mas não excluídas."]
    ];
    const instructionSheet=XLSX.utils.aoa_to_sheet(instructionRows);
    instructionSheet["!cols"]=[{wch:32},{wch:100}];

    const areaRows=[
      ["Código","Área","Ativa"],
      ...workAreas.map(area=>[area.code,area.name,area.active?"Sim":"Não"])
    ];
    const areaSheet=XLSX.utils.aoa_to_sheet(areaRows);
    areaSheet["!cols"]=[{wch:14},{wch:34},{wch:10}];
    areaSheet["!autofilter"]={ref:`A1:C${Math.max(areaRows.length,2)}`};

    XLSX.utils.book_append_sheet(workbook,activitySheet,"Atividades");
    XLSX.utils.book_append_sheet(workbook,instructionSheet,"Instruções");
    XLSX.utils.book_append_sheet(workbook,areaSheet,"Áreas");

    XLSX.writeFile(workbook,`Lista_Atividades_Aponta_P3_${today()}.xlsx`);
    setActivityWorkbookStatus(`${rows.length} atividades exportadas para Excel.`);
  }

  async function parseActivitiesWorkbook(file){
    if(!window.XLSX)throw new Error("Biblioteca de Excel não carregada.");
    if(!file)throw new Error("Selecione o arquivo de atividades.");
    if(file.size>10*1024*1024)throw new Error("O arquivo deve ter no máximo 10 MB.");

    const arrayBuffer=await file.arrayBuffer();
    const workbook=XLSX.read(arrayBuffer,{type:"array",cellDates:false});

    const sheetName=workbook.SheetNames.find(name=>
      normalizeText(name)==="atividades"
    )||workbook.SheetNames[0];

    if(!sheetName)throw new Error("O arquivo não possui nenhuma planilha.");

    const rawRows=XLSX.utils.sheet_to_json(workbook.Sheets[sheetName],{
      defval:"",
      raw:false
    });

    const rows=[];
    const duplicateCodes=new Set();
    const duplicateNames=new Set();
    const seenCodes=new Set();
    const seenNames=new Set();

    rawRows.forEach((rawRow,index)=>{
      const row=activityWorkbookRowMap(rawRow);
      const id=String(workbookValue(row,["ID","atividade_id"])||"").trim();
      const code=normalizeActivityCode(workbookValue(row,["Código","Codigo","code"]));
      const name=String(workbookValue(row,["Atividade","Nome","activity","name"])||"").trim();
      const disciplineName=String(workbookValue(row,["Disciplina","discipline_name"])||"").trim();
      const nature=String(workbookValue(row,["Natureza","nature"])||"").trim();
      const usageDescription=String(workbookValue(row,[
        "Orientação de uso",
        "Orientacao de uso",
        "usage_description"
      ])||"").trim();

      if(!id&&!code&&!name)return;
      if(!name)throw new Error(`Linha ${index+2}: informe o nome da atividade.`);

      const current=
        activities.find(activity=>activity.id===id)||
        (code?activities.find(activity=>normalizeActivityCode(activity.code)===code):null)||
        activities.find(activity=>normalizeText(activity.name)===normalizeText(name));

      const observationRequirement=parseSpreadsheetObservationRequirement(
        workbookValue(row,[
          "Observação",
          "Observacao",
          "Observação obrigatória",
          "Observacao obrigatoria",
          "observation_requirement"
        ]),
        current?.observation_requirement||"Opcional"
      );

      const active=parseSpreadsheetActive(
        workbookValue(row,["Status","Ativo","Active"]),
        current?.active??true
      );

      const areaResult=parseSpreadsheetAreas(row);
      if(areaResult.invalid.length){
        throw new Error(
          `Linha ${index+2}: área(s) inválida(s): ${areaResult.invalid.join(", ")}.`
        );
      }
      if(!areaResult.codes.length){
        throw new Error(`Linha ${index+2}: informe pelo menos uma área aplicável.`);
      }

      if(code){
        if(seenCodes.has(code))duplicateCodes.add(code);
        seenCodes.add(code);
      }

      const normalizedName=normalizeText(name);
      if(seenNames.has(normalizedName))duplicateNames.add(name);
      seenNames.add(normalizedName);

      rows.push({
        row_number:index+2,
        id:id||null,
        code:code||null,
        name,
        discipline_name:disciplineName,
        nature,
        usage_description:usageDescription,
        observation_requirement:observationRequirement,
        active,
        areas:areaResult.codes
      });
    });

    if(!rows.length)throw new Error("Nenhuma atividade válida foi encontrada no arquivo.");
    if(duplicateCodes.size){
      throw new Error(`Códigos repetidos no arquivo: ${[...duplicateCodes].join(", ")}.`);
    }
    if(duplicateNames.size){
      throw new Error(`Atividades repetidas no arquivo: ${[...duplicateNames].join(", ")}.`);
    }

    return rows;
  }

  async function uploadActivitiesWorkbook(file){
    if(!isAdmin()){
      toast("Somente o Administrador pode enviar a lista de atividades.",true);
      return;
    }

    showLoading(true);
    setActivityWorkbookStatus("Lendo e validando o arquivo...");

    try{
      const rows=await parseActivitiesWorkbook(file);
      let predictedCreated=0;
      let predictedUpdated=0;

      rows.forEach(row=>{
        const existing=
          (row.id&&activities.some(activity=>activity.id===row.id))||
          (row.code&&activities.some(activity=>normalizeActivityCode(activity.code)===row.code))||
          activities.some(activity=>normalizeText(activity.name)===normalizeText(row.name));

        if(existing)predictedUpdated+=1;
        else predictedCreated+=1;
      });

      const confirmed=window.confirm(
        `Importar ${rows.length} atividade${rows.length===1?"":"s"}?\n\n`+
        `${predictedUpdated} serão atualizadas e ${predictedCreated} serão criadas.\n\n`+
        "As linhas ausentes no Excel não serão excluídas."
      );
      if(!confirmed){
        setActivityWorkbookStatus("Importação cancelada.");
        return;
      }

      setActivityWorkbookStatus(`Importando ${rows.length} atividades...`);

      const {data,error}=await sb.rpc(
        "aponta_import_activities_v2180",
        {p_rows:rows}
      );

      if(error)throw error;

      clearActivitySelection();
      await reloadCatalogs();

      const created=Number(data?.created||0);
      const updated=Number(data?.updated||0);
      setActivityWorkbookStatus(
        `Importação concluída: ${created} criada${created===1?"":"s"} e `+
        `${updated} atualizada${updated===1?"":"s"}.`
      );
      toast("Lista de atividades atualizada.");
    }catch(error){
      console.error(error);
      setActivityWorkbookStatus(
        error?.message||
        "Não foi possível importar a lista de atividades.",
        true
      );
      toast(
        error?.message||
        "Não foi possível importar a lista de atividades.",
        true
      );
    }finally{
      showLoading(false);
      const input=$("activitiesWorkbookFile");
      if(input)input.value="";
    }
  }

  /* APONTA P3 v2.19.11 — disciplina, natureza e sequência de códigos */
  const ACTIVITY_NATURE_DEFAULTS = [
    "Rotina / Demanda",
    "Planejada / Demanda",
    "Demanda / Emergencial",
    "Demanda / Validação",
    "Validação / Demanda",
    "Rotina / Planejada",
    "Planejada / Rotina",
    "Melhoria"
  ];

  function activityCodeParts(value){
    const normalized=normalizeActivityCode(value);
    const match=normalized.match(/^([A-Z0-9]+)-(\d+)$/);
    if(!match)return null;
    return {
      prefix:match[1],
      number:Number(match[2]),
      digits:match[2].length,
      code:normalized
    };
  }

  function inferActivityDisciplinePrefix(disciplineName){
    const normalizedDiscipline=normalizeText(disciplineName);
    if(!normalizedDiscipline)return "";

    const counts=new Map();
    activities
      .filter(activity=>
        normalizeText(activity.discipline_name)===normalizedDiscipline
      )
      .forEach(activity=>{
        const parts=activityCodeParts(activity.code);
        if(!parts)return;
        counts.set(parts.prefix,(counts.get(parts.prefix)||0)+1);
      });

    return [...counts.entries()]
      .sort((a,b)=>b[1]-a[1]||a[0].localeCompare(b[0],"pt-BR"))[0]?.[0]||"";
  }

  function activityDisciplineOptions(){
    const rows=new Map();

    activities.forEach(activity=>{
      const name=String(activity.discipline_name||"").trim();
      if(!name)return;

      const key=normalizeText(name);
      if(!rows.has(key)){
        rows.set(key,{
          name,
          prefix:inferActivityDisciplinePrefix(name)
        });
      }
    });

    return [...rows.values()].sort((a,b)=>
      String(a.prefix||"").localeCompare(
        String(b.prefix||""),
        "pt-BR",
        {numeric:true,sensitivity:"base"}
      )||
      a.name.localeCompare(b.name,"pt-BR",{sensitivity:"base"})
    );
  }

  function activityNatureOptions(){
    const values=[];
    const seen=new Set();

    [...ACTIVITY_NATURE_DEFAULTS,
      ...activities.map(activity=>String(activity.nature||"").trim())
    ].forEach(value=>{
      const clean=String(value||"").trim();
      const key=normalizeText(clean);
      if(!clean||seen.has(key))return;
      seen.add(key);
      values.push(clean);
    });

    return values;
  }

  function fillActivityFormSelect(
    selectId,
    rows,
    placeholder,
    labelFn,
    valueFn,
    preferredValue=""
  ){
    const select=$(selectId);
    if(!select)return;

    const selectedValue=preferredValue||select.value||"";
    select.innerHTML=
      `<option value="">${esc(placeholder)}</option>`+
      rows.map(row=>
        `<option value="${esc(valueFn(row))}">${esc(labelFn(row))}</option>`
      ).join("");

    if(
      selectedValue&&
      [...select.options].some(option=>option.value===selectedValue)
    ){
      select.value=selectedValue;
    }else{
      select.value="";
    }
  }

  function populateActivityFormOptions(
    preferredDiscipline="",
    preferredNature=""
  ){
    const disciplines=activityDisciplineOptions();
    const natures=activityNatureOptions();

    fillActivityFormSelect(
      "activityDiscipline",
      disciplines,
      "Selecione a disciplina",
      row=>row.prefix?`${row.prefix} — ${row.name}`:row.name,
      row=>row.name
    );

    fillActivityFormSelect(
      "activityNature",
      natures,
      "Selecione a natureza",
      value=>value,
      value=>value
    );

    fillActivityFormSelect(
      "editActivityDiscipline",
      disciplines,
      "Selecione a disciplina",
      row=>row.prefix?`${row.prefix} — ${row.name}`:row.name,
      row=>row.name,
      preferredDiscipline
    );

    fillActivityFormSelect(
      "editActivityNature",
      natures,
      "Selecione a natureza",
      value=>value,
      value=>value,
      preferredNature
    );

    updateActivityCodeSequence("create",false);
    updateActivityCodeSequence("edit",false);
  }

  function activityCodeSequence(disciplineName){
    const discipline=String(disciplineName||"").trim();
    if(!discipline)return null;

    const prefix=inferActivityDisciplinePrefix(discipline);
    if(!prefix){
      return {
        discipline,
        prefix:"",
        latest:"",
        next:""
      };
    }

    let greatest=0;
    let greatestDigits=3;
    let latest="";

    activities
      .filter(activity=>
        normalizeText(activity.discipline_name)===normalizeText(discipline)
      )
      .forEach(activity=>{
        const parts=activityCodeParts(activity.code);
        if(!parts||parts.prefix!==prefix)return;

        if(parts.number>greatest){
          greatest=parts.number;
          greatestDigits=Math.max(3,parts.digits);
          latest=parts.code;
        }
      });

    const nextNumber=greatest+1;
    const next=`${prefix}-${String(nextNumber).padStart(greatestDigits,"0")}`;

    return {
      discipline,
      prefix,
      latest,
      next
    };
  }

  function updateActivityCodeSequence(mode="create",autoFill=false){
    const editing=mode==="edit";
    const discipline=$(editing?"editActivityDiscipline":"activityDiscipline");
    const code=$(editing?"editActivityCode":"activityCode");
    const hint=$(editing?"editActivityCodeSequenceHint":"activityCodeSequenceHint");

    if(!discipline||!code||!hint)return;

    const sequence=activityCodeSequence(discipline.value);

    if(!sequence){
      hint.textContent=
        "Selecione a disciplina para consultar o último código cadastrado.";
      if(!editing)code.placeholder="Selecione primeiro a disciplina";
      return;
    }

    if(!sequence.prefix){
      hint.textContent=
        "Nenhum prefixo foi encontrado para esta disciplina. Informe o código manualmente.";
      code.placeholder="Informe o código";
      return;
    }

    if(sequence.latest){
      hint.textContent=
        `Último código cadastrado: ${sequence.latest} • `+
        `Próximo sugerido: ${sequence.next}`;
    }else{
      hint.textContent=
        `Nenhum código cadastrado nesta disciplina • `+
        `Primeiro sugerido: ${sequence.next}`;
    }

    code.placeholder=sequence.next;

    if(
      autoFill&&
      !editing&&
      (!code.value.trim()||code.dataset.sequenceSuggested==="true")
    ){
      code.value=sequence.next;
      code.dataset.sequenceSuggested="true";
    }
  }

  $("activityDiscipline")?.addEventListener("change",()=>{
    updateActivityCodeSequence("create",true);
  });

  $("editActivityDiscipline")?.addEventListener("change",()=>{
    updateActivityCodeSequence("edit",false);
  });

  $("activityCode")?.addEventListener("input",()=>{
    $("activityCode").dataset.sequenceSuggested="false";
  });

  function populateActivityFilterOptions(){
    const areaSelect=$("activityFilterArea");
    const disciplineSelect=$("activityFilterDiscipline");
    if(!areaSelect||!disciplineSelect)return;

    const currentArea=areaSelect.value;
    const currentDiscipline=disciplineSelect.value;

    areaSelect.innerHTML=optionsWithPlaceholder(
      [...workAreas].sort((a,b)=>a.name.localeCompare(b.name,"pt-BR")),
      area=>`${area.code} — ${area.name}`,
      area=>area.code,
      "Todas as áreas"
    );

    const disciplines=[...new Set(
      activities
        .map(activity=>String(activity.discipline_name||"").trim())
        .filter(Boolean)
    )].sort((a,b)=>a.localeCompare(b,"pt-BR"));

    disciplineSelect.innerHTML=`<option value="">Todas as disciplinas</option>`+
      disciplines.map(value=>`<option value="${esc(value)}">${esc(value)}</option>`).join("");

    if([...areaSelect.options].some(option=>option.value===currentArea)){
      areaSelect.value=currentArea;
    }
    if([...disciplineSelect.options].some(option=>option.value===currentDiscipline)){
      disciplineSelect.value=currentDiscipline;
    }
  }

  function filteredCatalogActivities(){
    const search=normalizeText($("activityFilterSearch")?.value);
    const area=$("activityFilterArea")?.value||"";
    const discipline=$("activityFilterDiscipline")?.value||"";
    const observation=$("activityFilterObservation")?.value||"";
    const status=$("activityFilterStatus")?.value||"";

    return activities.filter(activity=>{
      const areas=activityAreas(activity.id);
      const searchable=normalizeText([
        activity.code,
        activity.name,
        activity.discipline_name,
        activity.nature,
        activity.usage_description,
        ...areas,
        ...areas.map(areaName)
      ].join(" "));

      if(search&&!searchable.includes(search))return false;
      if(area&&!areas.includes(area))return false;
      if(discipline&&activity.discipline_name!==discipline)return false;
      if(observation&&normalizeObservationRequirement(activity.observation_requirement)!==observation)return false;
      if(status==="ativa"&&!activity.active)return false;
      if(status==="inativa"&&activity.active)return false;
      return true;
    });
  }

  function renderActivitiesCatalog(){
    populateActivityFormOptions();
    populateActivityFilterOptions();
    const rows=filteredCatalogActivities();
    const total=activities.length;
    const filtered=rows.length!==total||Boolean(
      $("activityFilterSearch")?.value||
      $("activityFilterArea")?.value||
      $("activityFilterDiscipline")?.value||
      $("activityFilterObservation")?.value||
      $("activityFilterStatus")?.value
    );

    $("activityCatalogCount").textContent=filtered
      ?`${rows.length} de ${total} atividades`
      :`${total} atividades`;

    const resultCount=$("activityFilterResultCount");
    if(resultCount){
      resultCount.textContent=`${rows.length} resultado${rows.length===1?"":"s"}`;
    }

    visibleActivityIds=rows.map(activity=>activity.id);
    const existingActivityIds=new Set(activities.map(activity=>activity.id));
    Array.from(selectedActivityIds).forEach(id=>{
      if(!existingActivityIds.has(id))selectedActivityIds.delete(id);
    });

    $("activitiesTable").innerHTML=rows.map(x=>`<tr>
      ${isAdmin()?`<td><input class="activity-row-selector" type="checkbox" data-select-activity="${x.id}" ${selectedActivityIds.has(x.id)?"checked":""} aria-label="Selecionar ${esc(x.name)}"></td>`:""}
      <td>${esc(x.code||"—")}</td>
      <td>${esc(x.name)}</td>
      <td>${esc(activityAreas(x.id).map(areaName).join(", ")||"—")}</td>
      <td>${esc(x.discipline_name||"—")}</td>
      <td><span class="badge observation-${normalizeObservationRequirement(x.observation_requirement)==="Obrigatória"?"required":"optional"}">${esc(normalizeObservationRequirement(x.observation_requirement))}</span></td>
      <td><span class="badge">${x.active?"Ativa":"Inativa"}</span></td>
      <td><div class="table-actions">
        <button class="btn primary small" data-edit-activity="${x.id}">Editar</button>
        <button class="btn secondary small" data-toggle-activity="${x.id}" data-active="${x.active}">${x.active?"Inativar":"Ativar"}</button>
        <button class="btn danger small" data-delete-activity="${x.id}">Excluir</button>
      </div></td>
    </tr>`).join("")||`<tr><td colspan="${isAdmin()?8:7}" class="empty">Nenhuma atividade encontrada com os filtros informados</td></tr>`;

    updateActivityBulkActions();
  }

  function renderProjectsCatalog(){
    const search=normalizeText($("projectFilterSearch")?.value||"");
    const status=$("projectFilterStatus")?.value||"";

    const rows=[...projects]
      .sort((a,b)=>{
        const nameComparison=String(a.name||"").localeCompare(
          String(b.name||""),
          "pt-BR"
        );
        if(nameComparison)return nameComparison;

        return String(a.code||"").localeCompare(
          String(b.code||""),
          "pt-BR"
        );
      })
      .filter(project=>{
        if(status==="active"&&!project.active)return false;
        if(status==="inactive"&&project.active)return false;

        if(search){
          const searchable=normalizeText([
            project.code,
            project.name,
            project.client_name,
            project.description
          ].join(" "));

          if(!searchable.includes(search))return false;
        }

        return true;
      });

    if($("projectCatalogCount")){
      $("projectCatalogCount").textContent=
        rows.length===projects.length
          ?`${projects.length} projeto${projects.length===1?"":"s"}`
          :`${rows.length} de ${projects.length} projetos`;
    }

    $("projectsTable").innerHTML=rows.map(project=>`<tr>
      <td>${esc(project.code||"—")}</td>
      <td>${esc(project.name||"—")}</td>
      <td>${esc(project.client_name||"—")}</td>
      <td><span class="badge">${project.active?"Ativo":"Inativo"}</span></td>
      <td>
        <div class="table-actions">
          <button class="btn primary small" data-edit-project="${project.id}">
            Editar
          </button>
          <button class="btn secondary small"
            data-toggle-project="${project.id}"
            data-active="${project.active}">
            ${project.active?"Inativar":"Ativar"}
          </button>
          <button class="btn danger small" data-delete-project="${project.id}">
            Excluir
          </button>
        </div>
      </td>
    </tr>`).join("")||(
      projects.length
        ?'<tr><td colspan="5" class="empty">Nenhum projeto encontrado com os filtros informados.</td></tr>'
        :'<tr><td colspan="5" class="empty">Nenhum projeto cadastrado.</td></tr>'
    );
  }

  async function renderCatalogs(){
    const admin=isAdmin();
    const adminEdit=(attribute,id,label="Editar")=>admin?`<button class="btn primary small" ${attribute}="${id}">${label}</button>`:"";

    renderProjectsCatalog();
    renderActivitiesCatalog();
    $("holidaysTable").innerHTML=holidays.map(x=>`<tr><td>${dateBR(x.holiday_date)}</td><td>${esc(x.name)}</td><td><div class="table-actions"><button class="btn primary small" data-edit-holiday="${x.id}">Editar</button><button class="btn danger small" data-delete-holiday="${x.id}">Excluir</button></div></td></tr>`).join("")||'<tr><td colspan="3" class="empty">Nenhum feriado</td></tr>';

    const sortedWorkAreas=[...workAreas].sort(
      (a,b)=>(a.order_index||0)-(b.order_index||0)||
      a.name.localeCompare(b.name,"pt-BR")
    );

    if($("workAreasCount")){
      $("workAreasCount").textContent=`${sortedWorkAreas.length} área${sortedWorkAreas.length===1?"":"s"}`;
    }

    $("workAreasTable").innerHTML=sortedWorkAreas.map(area=>`<tr>
      <td><strong>${esc(area.code)}</strong></td>
      <td>${esc(area.name)}</td>
      <td>${esc(areaDetailTypeLabel(area.detail_type))}</td>
      <td>${Number(area.order_index||0)}</td>
      <td><span class="badge">${area.active?"Ativa":"Inativa"}</span></td>
      <td><div class="table-actions">
        ${admin?`<button class="btn primary small" data-edit-work-area="${esc(area.code)}">Editar</button>`:""}
        ${admin?`<button class="btn secondary small" data-toggle-work-area="${esc(area.code)}" data-active="${area.active}">${area.active?"Inativar":"Ativar"}</button>`:""}
        ${admin?`<button class="btn danger small" data-delete-work-area="${esc(area.code)}">Excluir</button>`:""}
      </div></td>
    </tr>`).join("")||'<tr><td colspan="6" class="empty">Nenhuma área cadastrada</td></tr>';

    $("sectorsTable").innerHTML=manufacturingSectors.map(x=>`<tr><td>${esc(x.code||"—")}</td><td>${esc(x.name)}</td><td><span class="badge">${x.active?"Ativo":"Inativo"}</span></td><td><div class="table-actions">${adminEdit("data-edit-sector",x.id)}<button class="btn secondary small" data-toggle-sector="${x.id}" data-active="${x.active}">${x.active?"Inativar":"Ativar"}</button>${admin?`<button class="btn danger small" data-delete-sector="${x.id}">Excluir</button>`:""}</div></td></tr>`).join("")||'<tr><td colspan="4" class="empty">Nenhum setor cadastrado</td></tr>';
    $("panelTypesTable").innerHTML=panelTypes.map(x=>`<tr><td>${esc(x.code||"—")}</td><td>${esc(x.name)}</td><td><span class="badge">${x.active?"Ativo":"Inativo"}</span></td><td><div class="table-actions">${adminEdit("data-edit-panel",x.id)}<button class="btn secondary small" data-toggle-panel="${x.id}" data-active="${x.active}">${x.active?"Inativar":"Ativar"}</button>${admin?`<button class="btn danger small" data-delete-panel="${x.id}">Excluir</button>`:""}</div></td></tr>`).join("")||'<tr><td colspan="4" class="empty">Nenhum tipo de painel cadastrado</td></tr>';
    $("roomsTable").innerHTML=rooms.map(x=>`<tr><td>${esc(x.code||"—")}</td><td>${esc(x.name)}</td><td><span class="badge">${x.active?"Ativa":"Inativa"}</span></td><td><div class="table-actions">${adminEdit("data-edit-room",x.id)}<button class="btn secondary small" data-toggle-room="${x.id}" data-active="${x.active}">${x.active?"Inativar":"Ativar"}</button>${admin?`<button class="btn danger small" data-delete-room="${x.id}">Excluir</button>`:""}</div></td></tr>`).join("")||'<tr><td colspan="4" class="empty">Nenhuma sala cadastrada</td></tr>';

    fillProjectStructureSelects();
    renderProjectComposition();
    renderProjectStructureTables();
  }
  if($("projectFilterSearch")){
    $("projectFilterSearch").oninput=renderProjectsCatalog;
  }

  if($("projectFilterStatus")){
    $("projectFilterStatus").onchange=renderProjectsCatalog;
  }

  if($("clearProjectFiltersBtn")){
    $("clearProjectFiltersBtn").onclick=()=>{
      $("projectFilterSearch").value="";
      $("projectFilterStatus").value="";
      renderProjectsCatalog();
      $("projectFilterSearch").focus();
    };
  }

  $("projectsTable").onclick=async e=>{
    const editId=e.target.dataset.editProject;
    const toggleId=e.target.dataset.toggleProject;
    const deleteId=e.target.dataset.deleteProject;
    if(editId){
      const x=projects.find(p=>p.id===editId);
      $("editProjectId").value=x.id;$("editProjectCode").value=x.code||"";$("editProjectClient").value=x.client_name||"";$("editProjectName").value=x.name;$("editProjectDescription").value=x.description||"";$("editProjectActive").value=String(x.active);
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
      const{error}=await sb.from("projects").update({code:$("editProjectCode").value.trim()||null,client_name:$("editProjectClient").value.trim(),name:$("editProjectName").value.trim(),description:$("editProjectDescription").value.trim(),active:$("editProjectActive").value==="true"}).eq("id",$("editProjectId").value);
      if(error)throw error;$("editProjectDialog").close();toast("Projeto atualizado.");await reloadCatalogs();
    }catch(error){handleError(error)}finally{showLoading(false)}
  };

  const applyActivityFilters=()=>{
    clearActivitySelection();
    renderActivitiesCatalog();
  };

  $("activityFilterSearch").oninput=applyActivityFilters;
  $("activityFilterArea").onchange=applyActivityFilters;
  $("activityFilterDiscipline").onchange=applyActivityFilters;
  $("activityFilterObservation").onchange=applyActivityFilters;
  $("activityFilterStatus").onchange=applyActivityFilters;
  $("clearActivityFiltersBtn").onclick=()=>{
    $("activityFilterSearch").value="";
    $("activityFilterArea").value="";
    $("activityFilterDiscipline").value="";
    $("activityFilterObservation").value="";
    $("activityFilterStatus").value="";
    applyActivityFilters();
    $("activityFilterSearch").focus();
  };

  $("activitiesTable").onclick=async e=>{
    const selector=e.target.closest("[data-select-activity]");
    if(selector){
      const id=selector.dataset.selectActivity;
      if(selector.checked)selectedActivityIds.add(id);
      else selectedActivityIds.delete(id);
      updateActivityBulkActions();
      return;
    }

    const editId=e.target.dataset.editActivity;
    const toggleId=e.target.dataset.toggleActivity;
    const deleteId=e.target.dataset.deleteActivity;
    if(editId){
      const x=activities.find(a=>a.id===editId);
      populateActivityFormOptions(x.discipline_name||"",x.nature||"");
      $("editActivityId").value=x.id;
      $("editActivityCode").value=normalizeActivityCode(x.code);
      $("editActivityName").value=x.name;
      $("editActivityDiscipline").value=x.discipline_name||"";
      $("editActivityNature").value=x.nature||"";
      updateActivityCodeSequence("edit",false);
      $("editActivityObservationRequirement").value=normalizeObservationRequirement(
        x.observation_requirement
      );
      $("editActivityUsageDescription").value=x.usage_description||"";
      $("editActivityActive").value=String(x.active);

      $("editActivityDialog").showModal();
      renderActivityAreaCheckboxes(
        "editActivityAreasCheckboxes",
        activityAreas(x.id)
      );
    }
    if(toggleId){const{error}=await sb.from("activities").update({active:e.target.dataset.active!=="true"}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs()}
    if(deleteId&&confirm("Excluir esta atividade? Só é possível apagar atividades sem apontamentos.")){
      const{error}=await sb.rpc("aponta_delete_activity_v28",{p_id:deleteId});
      if(error)handleError(error,"Atividade com histórico deve ser inativada.");else{selectedActivityIds.delete(deleteId);toast("Atividade excluída.");reloadCatalogs()}
    }
  };
  $("selectAllVisibleActivities").onchange=e=>{
    visibleActivityIds.forEach(id=>{
      if(e.target.checked)selectedActivityIds.add(id);
      else selectedActivityIds.delete(id);
    });

    document.querySelectorAll("[data-select-activity]").forEach(input=>{
      input.checked=e.target.checked;
    });

    updateActivityBulkActions();
  };

  $("clearSelectedActivitiesBtn").onclick=clearActivitySelection;

  $("inactivateSelectedActivitiesBtn").onclick=async ()=>{
    if(!isAdmin())return toast("Somente o Administrador pode inativar atividades em massa.",true);

    const ids=Array.from(selectedActivityIds);
    if(!ids.length)return;

    if(!window.confirm(
      `Inativar ${ids.length} atividade${ids.length===1?"":"s"} selecionada${ids.length===1?"":"s"}?`
    ))return;

    showLoading(true);
    try{
      const {error}=await sb.from("activities").update({active:false}).in("id",ids);
      if(error)throw error;
      clearActivitySelection();
      await reloadCatalogs();
      toast(`${ids.length} atividade${ids.length===1?"":"s"} inativada${ids.length===1?"":"s"}.`);
    }catch(error){
      handleError(error);
    }finally{
      showLoading(false);
    }
  };

  $("deleteSelectedActivitiesBtn").onclick=async ()=>{
    if(!isAdmin())return toast("Somente o Administrador pode excluir atividades em massa.",true);

    const ids=Array.from(selectedActivityIds);
    if(!ids.length)return;

    const confirmed=window.confirm(
      `Excluir ${ids.length} atividade${ids.length===1?"":"s"} selecionada${ids.length===1?"":"s"}?\n\n`+
      "Atividades que possuem apontamentos não serão apagadas. Para elas, utilize Inativar selecionadas."
    );
    if(!confirmed)return;

    showLoading(true);
    try{
      const {data,error}=await sb.rpc(
        "aponta_bulk_delete_activities_v2177",
        {p_ids:ids}
      );
      if(error)throw error;

      const deleted=Number(data?.deleted||0);
      const blocked=Array.isArray(data?.blocked)?data.blocked:[];
      clearActivitySelection();
      await reloadCatalogs();

      if(blocked.length){
        setActivityWorkbookStatus(
          `${deleted} atividade${deleted===1?"":"s"} excluída${deleted===1?"":"s"}. `+
          `${blocked.length} bloqueada${blocked.length===1?"":"s"} porque possui${blocked.length===1?"":"em"} apontamentos.`,
          true
        );
        toast(
          `${deleted} excluída${deleted===1?"":"s"}; ${blocked.length} com histórico não foram apagadas.`,
          true
        );
      }else{
        setActivityWorkbookStatus(
          `${deleted} atividade${deleted===1?"":"s"} excluída${deleted===1?"":"s"}.`
        );
        toast(`${deleted} atividade${deleted===1?"":"s"} excluída${deleted===1?"":"s"}.`);
      }
    }catch(error){
      handleError(
        error,
        "Não foi possível excluir as atividades. Execute o SQL obrigatório da versão 2.17.7."
      );
    }finally{
      showLoading(false);
    }
  };

  $("downloadActivitiesWorkbookBtn").onclick=downloadActivitiesWorkbook;

  $("uploadActivitiesWorkbookBtn").onclick=()=>{
    if(!isAdmin())return toast("Somente o Administrador pode enviar a lista de atividades.",true);
    $("activitiesWorkbookFile").click();
  };

  $("activitiesWorkbookFile").onchange=async e=>{
    const [file]=e.target.files||[];
    if(file)await uploadActivitiesWorkbook(file);
  };

  $("saveActivityEditBtn").onclick=async e=>{
    e.preventDefault();
    showLoading(true);

    try{
      const id=$("editActivityId").value;
      const areas=checkedAreaCodes("editActivityAreasCheckboxes");

      if(!areas.length){
        throw new Error("Selecione pelo menos uma área para a atividade.");
      }

      const {data,error}=await sb.rpc(
        "aponta_save_activity_v2180",
        {
          p_activity_id:id,
          p_code:normalizeActivityCode($("editActivityCode").value)||null,
          p_name:$("editActivityName").value.trim(),
          p_discipline_name:$("editActivityDiscipline").value.trim(),
          p_nature:$("editActivityNature").value.trim(),
          p_usage_description:$("editActivityUsageDescription").value.trim(),
          p_observation_requirement:normalizeObservationRequirement(
            $("editActivityObservationRequirement").value
          ),
          p_active:$("editActivityActive").value==="true",
          p_areas:areas
        }
      );

      if(error)throw error;
      if(!data?.id)throw new Error("O banco não confirmou a atividade atualizada.");

      const confirmedAreas=applyConfirmedActivityAreas(
        id,
        Array.isArray(data.areas)?data.areas:areas
      );

      await reloadCatalogs();

      // A função SQL já conferiu os vínculos dentro da mesma transação.
      // Reaplica a resposta confirmada para impedir falso aviso por leitura antiga.
      applyConfirmedActivityAreas(id,confirmedAreas);
      renderActivitiesCatalog();

      $("editActivityDialog").close();
      toast(
        `Atividade atualizada com ${confirmedAreas.length} `+
        `área${confirmedAreas.length===1?"":"s"}.`
      );
    }catch(error){
      handleError(
        error,
        "Não foi possível atualizar a atividade. Execute o SQL obrigatório da versão 2.18.3."
      );
    }finally{
      showLoading(false);
    }
  };

  $("workAreaForm").onsubmit=async e=>{
    e.preventDefault();

    if(!isAdmin()){
      return toast("Somente o Administrador pode cadastrar áreas.",true);
    }

    const code=normalizeWorkAreaCode($("workAreaCode").value);
    if(!code){
      return toast("Informe um código válido para a área.",true);
    }

    showLoading(true);
    try{
      const {error}=await sb.rpc(
        "aponta_save_work_area_v2185",
        {
          p_original_code:null,
          p_code:code,
          p_name:$("workAreaName").value.trim(),
          p_detail_type:enforceWorkAreaDetailType(
            code,
            $("workAreaName").value.trim(),
            $("workAreaDetailType").value
          ),
          p_order_index:Number($("workAreaOrder").value||0),
          p_active:true
        }
      );

      if(error)throw error;

      $("workAreaForm").reset();
      $("workAreaDetailType").value="none";
      $("workAreaOrder").value="10";
      toast("Área adicionada.");
      await reloadCatalogs();
    }catch(error){
      handleError(
        error,
        "Não foi possível cadastrar a área. Execute o SQL obrigatório da versão 2.18.5."
      );
    }finally{
      showLoading(false);
    }
  };

  $("workAreasTable").onclick=async e=>{
    const button=e.target.closest("button");
    if(!button)return;

    const editCode=button.dataset.editWorkArea;
    const toggleCode=button.dataset.toggleWorkArea;
    const deleteCode=button.dataset.deleteWorkArea;

    if(editCode){
      const area=workAreas.find(item=>item.code===editCode);
      if(!area)return;

      const roomOnly=isRoomOnlyWorkArea(area.code,area.name);

      $("editWorkAreaOriginalCode").value=area.code;
      $("editWorkAreaCode").value=area.code;
      $("editWorkAreaName").value=area.name;
      $("editWorkAreaDetailType").value=roomOnly
        ?"room"
        :(area.detail_type||"none");
      $("editWorkAreaDetailType").disabled=roomOnly;
      $("editWorkAreaFlowLockNote").hidden=!roomOnly;
      $("editWorkAreaOrder").value=String(area.order_index||0);
      $("editWorkAreaActive").value=String(area.active);
      $("editWorkAreaDialog").showModal();
      return;
    }

    if(toggleCode){
      showLoading(true);
      try{
        const area=workAreas.find(item=>item.code===toggleCode);
        if(!area)throw new Error("Área não encontrada.");

        const {error}=await sb.rpc(
          "aponta_save_work_area_v2185",
          {
            p_original_code:area.code,
            p_code:area.code,
            p_name:area.name,
            p_detail_type:enforceWorkAreaDetailType(
              area.code,
              area.name,
              area.detail_type
            ),
            p_order_index:Number(area.order_index||0),
            p_active:button.dataset.active!=="true"
          }
        );

        if(error)throw error;
        await reloadCatalogs();
      }catch(error){
        handleError(error);
      }finally{
        showLoading(false);
      }
      return;
    }

    if(deleteCode){
      const area=workAreas.find(item=>item.code===deleteCode);
      if(!area)return;

      if(!confirm(
        `Excluir a área ${area.code} — ${area.name}?\n\n`+
        "Áreas usadas em atividades ou apontamentos não poderão ser excluídas."
      ))return;

      showLoading(true);
      try{
        const {error}=await sb.rpc(
          "aponta_delete_work_area_v2182",
          {p_code:area.code}
        );

        if(error)throw error;
        toast("Área excluída.");
        await reloadCatalogs();
      }catch(error){
        handleError(
          error,
          "Área com histórico ou vínculos deve ser inativada."
        );
      }finally{
        showLoading(false);
      }
    }
  };

  $("editWorkAreaDialog").addEventListener("close",()=>{
    $("editWorkAreaDetailType").disabled=false;
    $("editWorkAreaFlowLockNote").hidden=true;
  });

  $("saveWorkAreaEditBtn").onclick=async e=>{
    e.preventDefault();

    showLoading(true);
    try{
      const originalCode=$("editWorkAreaOriginalCode").value;

      const {error}=await sb.rpc(
        "aponta_save_work_area_v2185",
        {
          p_original_code:originalCode,
          p_code:originalCode,
          p_name:$("editWorkAreaName").value.trim(),
          p_detail_type:enforceWorkAreaDetailType(
            originalCode,
            $("editWorkAreaName").value.trim(),
            $("editWorkAreaDetailType").value
          ),
          p_order_index:Number($("editWorkAreaOrder").value||0),
          p_active:$("editWorkAreaActive").value==="true"
        }
      );

      if(error)throw error;

      $("editWorkAreaDialog").close();
      toast("Área atualizada.");
      await reloadCatalogs();
    }catch(error){
      handleError(
        error,
        "Não foi possível atualizar a área. Execute o SQL obrigatório da versão 2.18.5."
      );
    }finally{
      showLoading(false);
    }
  };

  $("sectorForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("manufacturing_sectors").insert({code:$("sectorCode").value.trim().toUpperCase(),name:$("sectorName").value.trim()});if(error)handleError(error);else{$("sectorForm").reset();toast("Setor adicionado.");await reloadCatalogs()}};
  $("panelTypeForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("panel_types").insert({code:$("panelTypeCode").value.trim().toUpperCase(),name:$("panelTypeName").value.trim()});if(error)handleError(error);else{$("panelTypeForm").reset();toast("Tipo de painel adicionado.");await reloadCatalogs()}};
  $("roomForm").onsubmit=async e=>{e.preventDefault();const{error}=await sb.from("rooms").insert({code:$("roomCode").value.trim().toUpperCase(),name:$("roomName").value.trim()});if(error)handleError(error);else{$("roomForm").reset();toast("Sala adicionada ao catálogo.");await reloadCatalogs()}};

  $("projectCompositionProject").onchange=()=>{
    const projectId=$("projectCompositionProject").value;
    selectedProjectRoomIds.clear();
    if($("projectRoomModuleProject"))$("projectRoomModuleProject").value=projectId;
    refreshProjectRoomModuleRoomSelect();
    renderProjectComposition();
    renderProjectStructureTables();
  };

  $("projectRoomInstanceRoom").onchange=()=>{const def=standardRoomDefinitionFor(rooms.find(row=>row.id===$("projectRoomInstanceRoom").value));if(def?.monoblock){$("projectRoomInstanceCount").value="1";$("projectRoomInstanceCount").max="1";$("projectRoomInstanceModuleCount").max=String(MAX_MONOBLOCK_MODULES);}else{$("projectRoomInstanceCount").removeAttribute("max");$("projectRoomInstanceModuleCount").removeAttribute("max");}};

  $("projectRoomInstanceForm").onsubmit=async e=>{e.preventDefault();showLoading(true);try{
    const projectId=$("projectCompositionProject").value,roomId=$("projectRoomInstanceRoom").value;
    const roomCount=Number($("projectRoomInstanceCount").value),moduleCount=Number($("projectRoomInstanceModuleCount").value);
    if(!projectId||!roomId)throw new Error("Selecione o projeto e o tipo de sala.");
    if(!Number.isInteger(roomCount)||roomCount<1)throw new Error("Informe uma quantidade válida de salas.");
    if(!Number.isInteger(moduleCount)||moduleCount<1)throw new Error("Informe uma quantidade válida de módulos por sala.");
    const room=rooms.find(row=>row.id===roomId),def=standardRoomDefinitionFor(room);
    if(def?.monoblock){if(roomCount!==1)throw new Error("O MONOBLOCO permite somente uma sala por projeto.");if(moduleCount>MAX_MONOBLOCK_MODULES)throw new Error(`O MONOBLOCO permite no máximo ${MAX_MONOBLOCK_MODULES} módulos.`);const other=projectRoomInstances.some(row=>row.project_id===projectId&&row.active&&row.room_id!==roomId);if(other)throw new Error("O MONOBLOCO não pode ser combinado com outras salas.");}else{const mono=projectRoomInstances.some(row=>row.project_id===projectId&&row.active&&standardRoomDefinitionFor(rooms.find(r=>r.id===row.room_id))?.monoblock);if(mono)throw new Error("Este projeto está configurado como MONOBLOCO. Remova-o antes de incluir outras salas.");}
    const existing=projectRoomInstances.filter(row=>row.project_id===projectId&&row.room_id===roomId);let next=Math.max(0,...existing.map(row=>Number(row.instance_number||0)))+1;const prefix=$("projectRoomInstanceNamePrefix").value.trim()||room.code||room.name;
    for(let i=0;i<roomCount;i++){const number=next++;const display=`${prefix} ${String(number).padStart(2,"0")}`;const code=`${safeStructureCode(prefix,"SALA")}-${String(number).padStart(2,"0")}`;const{data,error}=await sb.from("project_room_instances").insert({project_id:projectId,room_id:roomId,instance_number:number,code,display_name:display,order_index:number,active:true}).select("*").single();if(error)throw error;projectRoomInstances.push(data);await syncRoomInstanceModuleQuantity(data.id,moduleCount);}
    toast(`${roomCount} sala${roomCount===1?"":"s"} adicionada${roomCount===1?"":"s"}.`);
    $("projectRoomInstanceForm").reset();
    $("projectCompositionProject").value=projectId;
    if($("projectRoomModuleProject"))$("projectRoomModuleProject").value=projectId;
    $("projectRoomInstanceCount").value="1";
    $("projectRoomInstanceModuleCount").value="1";
    await reloadCatalogs();
  }catch(error){handleError(error)}finally{showLoading(false)}};

  $("projectRoomModuleProject").onchange=refreshProjectRoomModuleRoomSelect;
  $("projectRoomModuleRoom").onchange=()=>updateModulePartsEditorForInstance($("projectRoomModuleRoom").value,false);
  $("projectRoomModuleForm").onsubmit=async e=>{e.preventDefault();showLoading(true);try{const instanceId=$("projectRoomModuleRoom").value;const instance=projectRoomInstances.find(row=>row.id===instanceId);if(!instance)throw new Error("Selecione a sala específica.");const monoblock=isMonoblockRoomInstance(instanceId);const selectedProjectId=instance.project_id;const number=Number($("projectRoomModuleOrder").value||1);const lower=monoblock?false:$("projectRoomModuleLower").checked,upper=monoblock?false:$("projectRoomModuleUpper").checked;if(!monoblock&&!lower&&!upper)throw new Error("Habilite pelo menos uma parte do módulo.");const{error}=await sb.from("project_room_instance_modules").insert({room_instance_id:instanceId,module_number:number,code:$("projectRoomModuleCode").value.trim().toUpperCase(),display_name:$("projectRoomModuleName").value.trim(),order_index:number,has_lower_part:lower,has_upper_part:upper,active:true});if(error)throw error;$("projectRoomModuleForm").reset();$("projectRoomModuleProject").value=selectedProjectId;if($("projectCompositionProject"))$("projectCompositionProject").value=selectedProjectId;refreshProjectRoomModuleRoomSelect();$("projectRoomModuleLower").checked=true;$("projectRoomModuleUpper").checked=true;toast("Módulo adicionado.");await reloadCatalogs();}catch(error){handleError(error)}finally{showLoading(false)}};

  $("sectorsTable").onclick=async e=>{
    const button=e.target.closest("button");if(!button)return;
    const editId=button.dataset.editSector;
    const toggleId=button.dataset.toggleSector;
    const deleteId=button.dataset.deleteSector;
    if(editId){
      const row=manufacturingSectors.find(item=>item.id===editId);if(!row)return;
      $("editSectorId").value=row.id;$("editSectorCode").value=row.code||"";$("editSectorName").value=row.name||"";$("editSectorActive").value=String(row.active);$("editSectorDialog").showModal();return;
    }
    if(toggleId){const{error}=await sb.from("manufacturing_sectors").update({active:button.dataset.active!=="true"}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs()}
    if(deleteId&&confirm("Excluir este setor? Registros já usados deverão ser apenas inativados.")){const{error}=await sb.from("manufacturing_sectors").delete().eq("id",deleteId);if(error)handleError(error,"Setor utilizado em apontamentos deve ser inativado.");else{toast("Setor excluído.");reloadCatalogs()}}
  };

  $("panelTypesTable").onclick=async e=>{
    const button=e.target.closest("button");if(!button)return;
    const editId=button.dataset.editPanel;
    const toggleId=button.dataset.togglePanel;
    const deleteId=button.dataset.deletePanel;
    if(editId){
      const row=panelTypes.find(item=>item.id===editId);if(!row)return;
      $("editPanelTypeId").value=row.id;$("editPanelTypeCode").value=row.code||"";$("editPanelTypeName").value=row.name||"";$("editPanelTypeActive").value=String(row.active);$("editPanelTypeDialog").showModal();return;
    }
    if(toggleId){const{error}=await sb.from("panel_types").update({active:button.dataset.active!=="true"}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs()}
    if(deleteId&&confirm("Excluir este tipo de painel? Registros já usados deverão ser apenas inativados.")){const{error}=await sb.from("panel_types").delete().eq("id",deleteId);if(error)handleError(error,"Tipo de painel utilizado em apontamentos deve ser inativado.");else{toast("Tipo de painel excluído.");reloadCatalogs()}}
  };

  $("roomsTable").onclick=async e=>{
    const button=e.target.closest("button");if(!button)return;
    const editId=button.dataset.editRoom;
    const toggleId=button.dataset.toggleRoom;
    const deleteId=button.dataset.deleteRoom;
    if(editId){
      const row=rooms.find(item=>item.id===editId);if(!row)return;
      $("editRoomId").value=row.id;$("editRoomCode").value=row.code||"";$("editRoomName").value=row.name||"";$("editRoomActive").value=String(row.active);$("editRoomDialog").showModal();return;
    }
    if(toggleId){const{error}=await sb.from("rooms").update({active:button.dataset.active!=="true"}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs()}
    if(deleteId){
      if(projectRoomInstances.some(row=>row.room_id===deleteId))return toast("Remova primeiro as salas específicas dos projetos na subaba Composição do projeto.",true);
      if(confirm("Excluir esta sala do catálogo?")){const{error}=await sb.from("rooms").delete().eq("id",deleteId);if(error)handleError(error,"Sala utilizada em apontamentos deve ser inativada.");else{toast("Sala excluída.");reloadCatalogs()}}
    }
  };

  $("saveSectorEditBtn").onclick=async e=>{e.preventDefault();showLoading(true);try{const{error}=await sb.from("manufacturing_sectors").update({code:$("editSectorCode").value.trim().toUpperCase(),name:$("editSectorName").value.trim(),active:$("editSectorActive").value==="true"}).eq("id",$("editSectorId").value);if(error)throw error;$("editSectorDialog").close();toast("Setor atualizado.");await reloadCatalogs()}catch(error){handleError(error)}finally{showLoading(false)}};
  $("savePanelTypeEditBtn").onclick=async e=>{e.preventDefault();showLoading(true);try{const{error}=await sb.from("panel_types").update({code:$("editPanelTypeCode").value.trim().toUpperCase(),name:$("editPanelTypeName").value.trim(),active:$("editPanelTypeActive").value==="true"}).eq("id",$("editPanelTypeId").value);if(error)throw error;$("editPanelTypeDialog").close();toast("Tipo de painel atualizado.");await reloadCatalogs()}catch(error){handleError(error)}finally{showLoading(false)}};
  $("saveRoomEditBtn").onclick=async e=>{e.preventDefault();showLoading(true);try{const{error}=await sb.from("rooms").update({code:$("editRoomCode").value.trim().toUpperCase(),name:$("editRoomName").value.trim(),active:$("editRoomActive").value==="true"}).eq("id",$("editRoomId").value);if(error)throw error;$("editRoomDialog").close();toast("Sala atualizada.");await reloadCatalogs()}catch(error){handleError(error)}finally{showLoading(false)}};

  ["projectRoomsProjectFilter","projectRoomsTypeFilter","projectRoomsStatusFilter"].forEach(id=>{
    const element=$(id);
    if(element)element.onchange=renderProjectStructureTables;
  });

  if($("projectRoomsSearch")){
    $("projectRoomsSearch").oninput=renderProjectStructureTables;
  }

  if($("clearProjectRoomFiltersBtn")){
    $("clearProjectRoomFiltersBtn").onclick=()=>{
      $("projectRoomsSearch").value="";
      $("projectRoomsProjectFilter").value="";
      $("projectRoomsTypeFilter").value="";
      $("projectRoomsStatusFilter").value="";
      renderProjectStructureTables();
      $("projectRoomsSearch").focus();
    };
  }

  $("projectRoomsTable").onchange=e=>{
    const selector=e.target.closest('[data-select-room-instance]');
    if(!selector)return;
    if(selector.checked)selectedProjectRoomIds.add(selector.dataset.selectRoomInstance);
    else selectedProjectRoomIds.delete(selector.dataset.selectRoomInstance);
    updateProjectRoomBulkActions();
  };

  $("projectRoomsTable").onclick=async e=>{const button=e.target.closest("button");if(!button)return;const editId=button.dataset.editRoomInstance,toggleId=button.dataset.toggleRoomInstance,deleteId=button.dataset.deleteRoomInstance;
    if(editId){const row=projectRoomInstances.find(item=>item.id===editId);if(!row)return;$("editProjectRoomInstanceId").value=row.id;$("editProjectRoomProjectName").value=projectName(row.project_id);$("editProjectRoomCatalogName").value=roomCatalogName(row.room_id);$("editProjectRoomInstanceNumber").value=String(row.instance_number);$("editProjectRoomDisplayName").value=row.display_name;$("editProjectRoomModuleQuantity").value=String(instanceModuleCount(row.id));$("editProjectRoomOrder").value=String(row.order_index||0);$("editProjectRoomActive").value=String(row.active);$("editProjectRoomDialog").showModal();return;}
    if(toggleId){const{error}=await sb.from("project_room_instances").update({active:button.dataset.active!=="true",updated_at:new Date().toISOString()}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs();return;}
    if(deleteId&&confirm(`Excluir ${roomInstanceName(deleteId)}?`)){showLoading(true);try{await deleteRoomInstance(deleteId);selectedProjectRoomIds.delete(deleteId);toast("Sala excluída.");await reloadCatalogs()}catch(error){handleError(error,"Sala utilizada em apontamentos deve ser inativada.")}finally{showLoading(false)}}
  };

  $("selectAllProjectRooms").onchange=e=>{
    visibleProjectRoomIds().forEach(id=>{if(e.target.checked)selectedProjectRoomIds.add(id);else selectedProjectRoomIds.delete(id)});
    document.querySelectorAll('#projectRoomsTable [data-select-room-instance]').forEach(input=>input.checked=e.target.checked);
    updateProjectRoomBulkActions();
  };

  $("clearSelectedProjectRoomsBtn").onclick=()=>{
    selectedProjectRoomIds.clear();
    document.querySelectorAll('#projectRoomsTable [data-select-room-instance]').forEach(input=>input.checked=false);
    updateProjectRoomBulkActions();
  };

  $("inactivateSelectedProjectRoomsBtn").onclick=async()=>{
    const ids=Array.from(selectedProjectRoomIds);if(!ids.length)return;
    if(!confirm(`Inativar ${ids.length} sala${ids.length===1?'':'s'} selecionada${ids.length===1?'':'s'}?`))return;
    showLoading(true);
    try{
      const{error}=await sb.from('project_room_instances').update({active:false,updated_at:new Date().toISOString()}).in('id',ids);
      if(error)throw error;
      selectedProjectRoomIds.clear();toast(`${ids.length} sala${ids.length===1?'':'s'} inativada${ids.length===1?'':'s'}.`);await reloadCatalogs();
    }catch(error){handleError(error)}finally{showLoading(false)}
  };

  $("deleteSelectedProjectRoomsBtn").onclick=async()=>{
    const ids=Array.from(selectedProjectRoomIds);if(!ids.length)return;
    if(!confirm(`Excluir definitivamente ${ids.length} sala${ids.length===1?'':'s'} selecionada${ids.length===1?'':'s'}? Salas com histórico não serão apagadas.`))return;
    showLoading(true);
    const deleted=[],blocked=[];
    try{
      for(const id of ids){
        try{await deleteRoomInstance(id);deleted.push(id);selectedProjectRoomIds.delete(id)}
        catch(error){blocked.push({id,error})}
      }
      await reloadCatalogs();
      if(deleted.length)toast(`${deleted.length} sala${deleted.length===1?' excluída':'s excluídas'}.`);
      if(blocked.length)toast(`${blocked.length} sala${blocked.length===1?' possui':'s possuem'} histórico e deve${blocked.length===1?'':'m'} ser inativada${blocked.length===1?'':'s'}.`,true);
    }finally{showLoading(false)}
  };

  $("saveProjectRoomEditBtn").onclick=async e=>{e.preventDefault();showLoading(true);try{const id=$("editProjectRoomInstanceId").value;const row=projectRoomInstances.find(item=>item.id===id);const quantity=Number($("editProjectRoomModuleQuantity").value);const def=standardRoomDefinitionFor(rooms.find(room=>room.id===row?.room_id));if(!Number.isInteger(quantity)||quantity<1)throw new Error("Informe uma quantidade válida de módulos.");if(def?.monoblock&&quantity>MAX_MONOBLOCK_MODULES)throw new Error(`O MONOBLOCO permite no máximo ${MAX_MONOBLOCK_MODULES} módulos.`);const{error}=await sb.from("project_room_instances").update({instance_number:Number($("editProjectRoomInstanceNumber").value),display_name:$("editProjectRoomDisplayName").value.trim(),order_index:Number($("editProjectRoomOrder").value||0),active:$("editProjectRoomActive").value==="true",updated_at:new Date().toISOString()}).eq("id",id);if(error)throw error;await syncRoomInstanceModuleQuantity(id,quantity);$("editProjectRoomDialog").close();toast("Sala atualizada.");await reloadCatalogs()}catch(error){handleError(error)}finally{showLoading(false)}};

  $("projectRoomModulesTable").onclick=async e=>{const button=e.target.closest("button");if(!button)return;const editId=button.dataset.editInstanceModule,toggleId=button.dataset.toggleInstanceModule,deleteId=button.dataset.deleteInstanceModule;
    if(editId){const row=projectRoomInstanceModules.find(item=>item.id===editId);const instance=projectRoomInstances.find(item=>item.id===row?.room_instance_id);if(!row||!instance)return;const monoblock=isMonoblockRoomInstance(instance.id);$("editProjectRoomInstanceModuleId").value=row.id;$("editProjectRoomModuleProjectName").value=projectName(instance.project_id);$("editProjectRoomModuleRoomName").value=roomInstanceName(instance.id);$("editProjectRoomModuleNumber").value=String(row.module_number);$("editProjectRoomModuleCode").value=row.code;$("editProjectRoomModuleDisplayName").value=row.display_name;$("editProjectRoomModuleOrder").value=String(row.order_index||0);$("editProjectRoomModuleLower").checked=monoblock?false:row.has_lower_part!==false;$("editProjectRoomModuleUpper").checked=monoblock?false:row.has_upper_part!==false;updateModulePartsEditorForInstance(instance.id,true);$("editProjectRoomModuleActive").value=String(row.active);$("editProjectRoomModuleDialog").showModal();return;}
    if(toggleId){const{error}=await sb.from("project_room_instance_modules").update({active:button.dataset.active!=="true",updated_at:new Date().toISOString()}).eq("id",toggleId);if(error)handleError(error);else reloadCatalogs();return;}
    if(deleteId&&confirm(`Excluir ${roomInstanceModuleName(deleteId)}?`)){showLoading(true);try{await deleteRoomInstanceModule(deleteId);toast("Módulo excluído.");await reloadCatalogs()}catch(error){handleError(error,"Módulo utilizado em apontamentos deve ser inativado.")}finally{showLoading(false)}}
  };

  $("saveProjectRoomModuleEditBtn").onclick=async e=>{e.preventDefault();showLoading(true);try{const id=$("editProjectRoomInstanceModuleId").value;const row=projectRoomInstanceModules.find(item=>item.id===id);const instance=projectRoomInstances.find(item=>item.id===row?.room_instance_id);const monoblock=isMonoblockRoomInstance(instance?.id);const lower=monoblock?false:$("editProjectRoomModuleLower").checked,upper=monoblock?false:$("editProjectRoomModuleUpper").checked;if(!monoblock&&!lower&&!upper)throw new Error("Habilite pelo menos uma parte do módulo.");const{error}=await sb.from("project_room_instance_modules").update({module_number:Number($("editProjectRoomModuleNumber").value),code:$("editProjectRoomModuleCode").value.trim().toUpperCase(),display_name:$("editProjectRoomModuleDisplayName").value.trim(),order_index:Number($("editProjectRoomModuleOrder").value||0),has_lower_part:lower,has_upper_part:upper,active:$("editProjectRoomModuleActive").value==="true",updated_at:new Date().toISOString()}).eq("id",id);if(error)throw error;$("editProjectRoomModuleDialog").close();toast("Módulo atualizado.");await reloadCatalogs()}catch(error){handleError(error)}finally{showLoading(false)}};

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
            const normalizedHours=Math.round(numericValue*100)/100;
            if (normalizedHours <= 0) return;
            if (normalizedHours > 24) {
              ignoredInvalid += 1;
              return;
            }
            if (date > today()) {
              ignoredFuture += 1;
              return;
            }

            entries.push({
              date,
              projectKey,
              activityKey,
              hours: normalizedHours,
              details:
                `Importado da planilha ${file.name}` +
                (detailRequired ? " — atividade marcada para detalhamento na planilha original." : "")
            });
            totalHours += normalizedHours;
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

  function formatImportError(error, stage="Importação"){
    const parts=[];
    if(error?.message)parts.push(error.message);
    if(error?.details&&error.details!==error.message)parts.push(error.details);
    if(error?.hint)parts.push(`Orientação: ${error.hint}`);
    if(error?.code)parts.push(`Código: ${error.code}`);
    return {
      stage,
      text:parts.filter(Boolean).join(" — ")||"Erro não identificado."
    };
  }

  function describeImportRow(table,row,index){
    if(table==="time_entries"){
      return `linha ${index+1}, data ${row.entry_date||"não informada"}, horas ${row.hours??"não informadas"}`;
    }
    if(table==="activities")return `atividade "${row.name||"sem nome"}"`;
    if(table==="projects")return `projeto "${row.name||"sem nome"}"`;
    if(table==="holidays")return `feriado ${row.holiday_date||"sem data"}`;
    return `registro ${index+1}`;
  }

  async function insertInChunks(table, rows, chunkSize = 200, options={}) {
    let inserted = 0;
    const ignoreDuplicate=options.ignoreDuplicate===true;

    for (let index = 0; index < rows.length; index += chunkSize) {
      const chunk = rows.slice(index, index + chunkSize);
      const {error} = await sb.from(table).insert(chunk);

      if(!error){
        inserted += chunk.length;
        continue;
      }

      // Repete individualmente para identificar o registro que falhou.
      for(let offset=0;offset<chunk.length;offset+=1){
        const row=chunk[offset];
        const {error:rowError}=await sb.from(table).insert(row);

        if(!rowError){
          inserted+=1;
          continue;
        }

        if(ignoreDuplicate&&rowError.code==="23505")continue;

        const detailedError=new Error(
          `${describeImportRow(table,row,index+offset)}: ${rowError.message||"erro ao gravar"}`
        );
        detailedError.code=rowError.code;
        detailedError.details=rowError.details;
        detailedError.hint=rowError.hint;
        throw detailedError;
      }
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

    let importStage="Preparação";
    try {
      let projectsCreated = 0;
      let activitiesCreated = 0;
      let entriesCreated = 0;
      let entriesSkipped = 0;
      let holidaysCreated = 0;
      let absencesCreated = 0;

      const analysis = excelImportAnalysis;

      if ($("importCatalogs").checked || $("importEntries").checked) {
        importStage="Projetos";
        setImportProgress(15, "Importando projetos...");

        const existingProjects = new Map(projects.map(project => [normalizeImportText(project.name), project]));
        const newProjects = analysis.projects
          .filter(project => !existingProjects.has(normalizeImportText(project.name)))
          .map(project => ({
            code: null,
            client_name: "",
            name: project.name,
            description: project.description || "",
            active: true,
            created_by: me.id
          }));

        if (newProjects.length) {
          projectsCreated = await insertInChunks("projects", newProjects, 100, {ignoreDuplicate:true});
        }

        importStage="Atividades";
        setImportProgress(25, "Importando atividades...");

        const existingActivities = new Map(activities.map(activity => [normalizeImportText(activity.name), activity]));
        const newActivities = analysis.activities
          .filter(activity => !existingActivities.has(normalizeImportText(activity.name)))
          .map(activity => ({
            code: null,
            name: activity.name,
            activity_type: activity.activity_type || "Demanda",
            frequency: activity.frequency || "",
            responsible_name: activity.responsible_name || "",
            backup_name: activity.backup_name || "",
            discipline_name: "Importação histórica",
            sector_principal: "Administrativo",
            nature: "Importada",
            usage_description: "Atividade criada pela importação da planilha histórica.",
            observation_requirement: "Opcional",
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
              observation_requirement: "Opcional",
              active: existing.active,
              created_by: existing.created_by || me.id
            };
          })
          .filter(Boolean);

        if (newActivities.length) {
          activitiesCreated = await insertInChunks("activities", newActivities, 100, {ignoreDuplicate:true});
        }

        if (activitiesToUpdate.length) {
          const {error: updateActivitiesError} = await sb
            .from("activities")
            .upsert(activitiesToUpdate, {onConflict: "id"});
          if (updateActivitiesError) throw updateActivitiesError;
        }

        await loadBaseData();
        const importedActivityIds=analysis.activities.map(item=>activities.find(row=>normalizeImportText(row.name)===normalizeImportText(item.name))?.id).filter(Boolean);
        if(importedActivityIds.length){
          const missingLinks=importedActivityIds.filter(id=>!activityAreaLinks.some(link=>link.activity_id===id));
          if(missingLinks.length){
            importStage="Vínculo das atividades com Administrativo";
            const{error:areaLinkError}=await sb
              .from("activity_area_links")
              .upsert(
                missingLinks.map(activity_id=>({activity_id,area_code:"ADM"})),
                {onConflict:"activity_id,area_code",ignoreDuplicates:true}
              );
            if(areaLinkError)throw areaLinkError;
            await loadBaseData();
          }
        }
      }

      if ($("importHolidays").checked && analysis.holidays.length) {
        importStage="Feriados";
        setImportProgress(35, "Importando feriados...");

        const existingHolidayDates = new Set(holidays.map(holiday => holiday.holiday_date));
        const newHolidays = analysis.holidays
          .filter(date => !existingHolidayDates.has(date))
          .map(date => ({holiday_date: date, name: "Feriado — importado da planilha"}));

        if (newHolidays.length) {
          holidaysCreated = await insertInChunks("holidays", newHolidays, 100, {ignoreDuplicate:true});
        }
      }

      if ($("importVacations").checked) {
        importStage="Férias e afastamentos";
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
        importStage="Preparação dos apontamentos";
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
              area_code: "ADM",
              sector_id: null,
              room_id: null,
              module_id: null,
              panel_type_id: null,
              project_room_instance_id: null,
              project_room_instance_module_id: null,
              module_part: null,
              hours: Math.round(Number(entry.hours)*100)/100,
              details: entry.details || "",
              status: "rascunho"
            });
          });
        }

        setImportProgress(70, `Importando ${rowsToInsert.length} apontamento(s)...`);

        importStage="Apontamentos";
        const chunkSize = 100;
        for (let index = 0; index < rowsToInsert.length; index += chunkSize) {
          const chunk = rowsToInsert.slice(index, index + chunkSize);
          const inserted=await insertInChunks("time_entries",chunk,chunkSize);
          entriesCreated += inserted;

          const fraction = rowsToInsert.length
            ? Math.min(index + chunk.length,rowsToInsert.length) / rowsToInsert.length
            : 1;
          setImportProgress(
            70 + Math.round(fraction * 25),
            `Importando apontamentos: ${entriesCreated}/${rowsToInsert.length}`
          );
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
      const diagnosis=formatImportError(error,importStage);
      console.error("Erro na importação do Aponta Horas",{
        stage:importStage,
        error
      });

      setImportProgress(100, `Importação interrompida em: ${importStage}.`);
      $("importResult").hidden = false;
      $("importResult").classList.add("error");
      $("importResult").innerHTML=`
        <h3>Não foi possível concluir a importação</h3>
        <p><strong>Etapa:</strong> ${esc(diagnosis.stage)}</p>
        <p><strong>Erro:</strong> ${esc(diagnosis.text)}</p>
        <p>Os registros concluídos antes dessa etapa podem ter sido gravados. Execute novamente após corrigir o erro; registros já existentes serão ignorados.</p>
      `;
      toast(`Erro na importação — ${diagnosis.stage}`,true);
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
        throw new Error("Este arquivo não foi reconhecido como backup do Aponta Horas.");
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
      const target=new URL("redefinir-senha.html",PRIMARY_APP_URL);
      target.search=window.location.search;
      target.hash=window.location.hash;

      if(!window.location.pathname.endsWith("/redefinir-senha.html")){
        window.location.replace(target.href);
      }
    }
  });

  if("serviceWorker" in navigator && location.protocol.startsWith("http")){
    navigator.serviceWorker
      .register("sw.js?v=2.19.12", {updateViaCache:"none"})
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


  // APONTA P3 v2.16.2 — transforma tabelas em cartões no celular
  function applyResponsiveTableLabels(root=document){
    const tables=root.querySelectorAll?.(".page .table-wrap table")||[];

    tables.forEach(table=>{
      table.classList.add("responsive-mobile-table");

      const headers=Array.from(table.querySelectorAll("thead th"))
        .map(header=>header.textContent.trim());

      table.querySelectorAll("tbody tr").forEach(row=>{
        const cells=Array.from(row.children).filter(
          cell=>cell.tagName==="TD"||cell.tagName==="TH"
        );

        if(cells.length===1&&Number(cells[0].getAttribute("colspan")||1)>1){
          cells[0].classList.add("mobile-empty-cell");
          cells[0].removeAttribute("data-label");
          return;
        }

        cells.forEach((cell,index)=>{
          const label=headers[index]||cell.getAttribute("data-label")||"Informação";
          cell.setAttribute("data-label",label);
        });
      });
    });
  }

  let responsiveTableFrame=0;

  function scheduleResponsiveTableLabels(){
    cancelAnimationFrame(responsiveTableFrame);
    responsiveTableFrame=requestAnimationFrame(()=>{
      applyResponsiveTableLabels(document);
    });
  }

  const responsiveTableRoot=document.getElementById("app");

  if(responsiveTableRoot){
    const responsiveTableObserver=new MutationObserver(()=>{
      scheduleResponsiveTableLabels();
    });

    responsiveTableObserver.observe(responsiveTableRoot,{
      childList:true,
      subtree:true
    });
  }

  window.addEventListener("resize",scheduleResponsiveTableLabels);
  document.addEventListener("DOMContentLoaded",scheduleResponsiveTableLabels);
  scheduleResponsiveTableLabels();



  ["activityCode","editActivityCode"].forEach(id=>{
    const input=$(id);
    if(!input)return;
    input.addEventListener("blur",()=>{
      input.value=normalizeActivityCode(input.value);
    });
  });

  // APONTA P3 v2.17.1 — caixas de seleção pesquisáveis em Apontamentos
  const SEARCHABLE_ENTRY_SELECT_IDS = [
    "entryUser",
    "entryProject",
    "entryArea",
    "entrySector",
    "entryPanelType",
    "entryRoom",
    "entryModule",
    "entryModulePart",
    "entryActivity",
    "filterEntryUser"
  ];

  const searchableSelectInstances = new Map();

  function normalizeSearchValue(value){
    return String(value||"")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g,"")
      .toLowerCase()
      .trim();
  }

  function setupSearchableSelect(select){
    if(!select||select.dataset.searchableReady==="true")return;

    select.dataset.searchableReady="true";

    const wrapper=document.createElement("div");
    wrapper.className="searchable-select";
    select.parentNode.insertBefore(wrapper,select);
    wrapper.appendChild(select);

    select.classList.add("searchable-select-native");
    select.tabIndex=-1;

    const input=document.createElement("input");
    input.type="search";
    input.className="searchable-select-input";
    input.autocomplete="off";
    input.spellcheck=false;
    input.setAttribute("role","combobox");
    input.setAttribute("aria-autocomplete","list");
    input.setAttribute("aria-expanded","false");

    const toggle=document.createElement("button");
    toggle.type="button";
    toggle.className="searchable-select-toggle";
    toggle.setAttribute("aria-label","Abrir opções");
    toggle.textContent="⌄";

    const list=document.createElement("div");
    list.className="searchable-select-list";
    list.setAttribute("role","listbox");
    list.hidden=true;

    wrapper.append(input,toggle,list);

    let activeIndex=-1;
    let renderedOptions=[];
    let transferringRequired=false;

    const getPlaceholder=()=>{
      const emptyOption=Array.from(select.options).find(option=>!option.value);
      return emptyOption?.textContent?.trim()||"Digite para buscar";
    };

    const optionRows=()=>Array.from(select.options)
      .filter(option=>option.value&&!option.disabled)
      .map(option=>({
        value:option.value,
        text:option.textContent.trim(),
        search:normalizeSearchValue(
          `${option.textContent} ${option.value} ${option.dataset.search||""}`
        )
      }));

    const selectedText=()=>{
      const option=select.selectedOptions?.[0];
      return option?.value?option.textContent.trim():"";
    };

    const closeList=()=>{
      list.hidden=true;
      input.setAttribute("aria-expanded","false");
      activeIndex=-1;
    };

    const markActive=()=>{
      const buttons=[...list.querySelectorAll(".searchable-select-option")];
      buttons.forEach((button,index)=>{
        const active=index===activeIndex;
        button.classList.toggle("active",active);
        button.setAttribute("aria-selected",String(active));
        if(active)button.scrollIntoView({block:"nearest"});
      });
    };

    const chooseOption=row=>{
      select.value=row.value;
      input.value=row.text;
      input.setCustomValidity("");
      select.dispatchEvent(new Event("input",{bubbles:true}));
      select.dispatchEvent(new Event("change",{bubbles:true}));
      closeList();
    };

    const renderOptions=(query="")=>{
      const normalized=normalizeSearchValue(query);
      const allRows=optionRows();

      renderedOptions=allRows
        .filter(row=>!normalized||row.search.includes(normalized))
        .sort((a,b)=>{
          if(!normalized)return a.text.localeCompare(b.text,"pt-BR");
          const aStarts=normalizeSearchValue(a.text).startsWith(normalized)?0:1;
          const bStarts=normalizeSearchValue(b.text).startsWith(normalized)?0:1;
          return aStarts-bStarts||a.text.localeCompare(b.text,"pt-BR");
        });

      const visibleRows=renderedOptions.slice(0,120);

      if(!visibleRows.length){
        list.innerHTML='<div class="searchable-select-empty">Nenhuma opção encontrada.</div>';
      }else{
        list.innerHTML=visibleRows.map((row,index)=>`
          <button
            type="button"
            class="searchable-select-option"
            role="option"
            data-option-index="${index}">
            ${esc(row.text)}
          </button>
        `).join("");

        if(renderedOptions.length>visibleRows.length){
          list.insertAdjacentHTML(
            "beforeend",
            '<div class="searchable-select-more">Digite mais letras para refinar a busca.</div>'
          );
        }
      }

      activeIndex=visibleRows.length?0:-1;
      list.hidden=false;
      input.setAttribute("aria-expanded","true");
      markActive();
    };

    const transferRequired=()=>{
      if(transferringRequired)return;
      transferringRequired=true;
      const shouldRequire=select.required;
      input.required=shouldRequire;
      if(select.required)select.required=false;
      transferringRequired=false;
    };

    const syncState=()=>{
      transferRequired();
      input.disabled=select.disabled;
      toggle.disabled=select.disabled;
      input.placeholder=getPlaceholder();

      const text=selectedText();
      if(document.activeElement!==input||!input.value){
        input.value=text;
      }

      if(select.value){
        input.setCustomValidity("");
      }

      wrapper.classList.toggle("disabled",select.disabled);
    };

    input.addEventListener("focus",()=>{
      if(select.disabled)return;
      input.select();
      renderOptions(input.value);
    });

    input.addEventListener("click",()=>{
      if(select.disabled)return;
      renderOptions(input.value);
    });

    input.addEventListener("input",()=>{
      const exact=optionRows().find(
        row=>normalizeSearchValue(row.text)===normalizeSearchValue(input.value)
      );

      if(exact){
        select.value=exact.value;
        input.setCustomValidity("");
      }else{
        select.value="";
        if(input.value.trim()){
          input.setCustomValidity("Selecione uma opção exibida na lista.");
        }else{
          input.setCustomValidity(input.required?"Selecione uma opção.":"");
        }
      }

      renderOptions(input.value);
    });

    input.addEventListener("keydown",event=>{
      if(event.key==="ArrowDown"){
        event.preventDefault();
        if(list.hidden)renderOptions(input.value);
        const count=Math.min(renderedOptions.length,120);
        if(count){
          activeIndex=(activeIndex+1)%count;
          markActive();
        }
      }else if(event.key==="ArrowUp"){
        event.preventDefault();
        if(list.hidden)renderOptions(input.value);
        const count=Math.min(renderedOptions.length,120);
        if(count){
          activeIndex=(activeIndex-1+count)%count;
          markActive();
        }
      }else if(event.key==="Enter"&&!list.hidden){
        event.preventDefault();
        const row=renderedOptions[activeIndex];
        if(row)chooseOption(row);
      }else if(event.key==="Escape"){
        closeList();
        input.value=selectedText();
        input.setCustomValidity("");
      }
    });

    input.addEventListener("blur",()=>{
      window.setTimeout(()=>{
        if(wrapper.contains(document.activeElement))return;

        const exact=optionRows().find(
          row=>normalizeSearchValue(row.text)===normalizeSearchValue(input.value)
        );

        if(exact&&!select.value){
          chooseOption(exact);
        }else if(!select.value){
          input.value="";
          input.setCustomValidity(input.required?"Selecione uma opção.":"");
        }else{
          input.value=selectedText();
          input.setCustomValidity("");
        }

        closeList();
      },120);
    });

    toggle.addEventListener("click",()=>{
      if(select.disabled)return;
      if(list.hidden){
        input.focus();
        renderOptions("");
      }else{
        closeList();
      }
    });

    list.addEventListener("mousedown",event=>{
      event.preventDefault();
    });

    list.addEventListener("click",event=>{
      const button=event.target.closest(".searchable-select-option");
      if(!button)return;
      const row=renderedOptions[Number(button.dataset.optionIndex)];
      if(row)chooseOption(row);
    });

    select.addEventListener("change",syncState);
    select.addEventListener("input",syncState);

    const observer=new MutationObserver(()=>{
      window.requestAnimationFrame(syncState);
    });

    observer.observe(select,{
      childList:true,
      subtree:true,
      attributes:true,
      attributeFilter:["disabled","required"]
    });

    select.form?.addEventListener("reset",()=>{
      window.setTimeout(syncState,0);
    });

    searchableSelectInstances.set(select.id,{
      select,
      input,
      wrapper,
      list,
      syncState,
      closeList
    });

    syncState();
  }

  function initializeSearchableEntrySelects(){
    SEARCHABLE_ENTRY_SELECT_IDS.forEach(id=>{
      setupSearchableSelect($(id));
    });
  }

  document.addEventListener("click",event=>{
    searchableSelectInstances.forEach(instance=>{
      if(!instance.wrapper.contains(event.target)){
        instance.closeList();
      }
    });
  });

  initializeSearchableEntrySelects();

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

  const INSTALL_DISMISS_KEY = "aponta-p3-install-dismissed-session";

  function installPromptWasRecentlyDismissed() {
    return sessionStorage.getItem(INSTALL_DISMISS_KEY)==="1";
  }

  function hideInstallAppOverlay(remember = true) {
    const overlay = document.getElementById("installAppOverlay");
    if (overlay) overlay.hidden = true;
    if (remember) {
      sessionStorage.setItem(INSTALL_DISMISS_KEY, "1");
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
      setTimeout(() => showInstallAppOverlay("android"), 150);
    }
  });

  window.addEventListener("appinstalled", () => {
    deferredInstallPrompt = null;
    sessionStorage.removeItem(INSTALL_DISMISS_KEY);
    hideInstallAppOverlay(false);
    try {
      toast("Aponta Horas instalado com sucesso.");
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
    }, 350);
  });

  window.APONTA_P3_VERSION = "2.19.12";
})();
