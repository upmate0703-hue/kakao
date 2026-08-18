#!/usr/bin/osascript -l JavaScript
//
// 카카오 발송기 (맥용) v0.1
//
// 맥 카카오톡은 화면 구조가 Windows 판과 완전히 다릅니다.
// 그래서 Windows 판을 만들 때와 같은 순서로 갑니다.
//   1) dump 로 화면 구조를 눈으로 확인하고
//   2) 확인된 것만 자동화합니다.
//
// 사용법:
//   osascript -l JavaScript kakao-mac.js check
//   osascript -l JavaScript kakao-mac.js dump [깊이]
//   osascript -l JavaScript kakao-mac.js rooms
//   osascript -l JavaScript kakao-mac.js open "방이름"
//   osascript -l JavaScript kakao-mac.js send "방이름" "보낼 글"          (확인만, 전송 안 함)
//   osascript -l JavaScript kakao-mac.js send "방이름" "보낼 글" --live   (실제 전송)
//
ObjC.import('stdlib');

const KAKAO_NAMES = ['KakaoTalk', '카카오톡', 'Kakaotalk'];
const MAX_DUMP_NODES = 4000;

function out(text) {
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(
    $.NSString.alloc.initWithUTF8String(text + '\n').dataUsingEncoding($.NSUTF8StringEncoding)
  );
}

function systemEvents() {
  const se = Application('System Events');
  se.includeStandardAdditions = true;
  return se;
}

// 손쉬운 사용(접근성) 권한이 있어야 다른 앱 화면을 읽고 조작할 수 있습니다.
function hasAccessibility(se) {
  try {
    return se.uiElementsEnabled();
  } catch (e) {
    return false;
  }
}

function findKakaoProcess(se) {
  const processes = se.applicationProcesses;
  for (let i = 0; i < KAKAO_NAMES.length; i++) {
    try {
      const proc = processes.byName(KAKAO_NAMES[i]);
      if (proc.exists()) { return proc; }
    } catch (e) { /* 이름이 다르면 다음으로 */ }
  }
  // 이름을 못 찾으면 실행 중인 목록에서 비슷한 것을 찾습니다.
  try {
    const all = processes.name();
    for (let i = 0; i < all.length; i++) {
      const name = String(all[i]);
      if (name.toLowerCase().indexOf('kakao') >= 0 || name.indexOf('카카오') >= 0) {
        return processes.byName(all[i]);
      }
    }
  } catch (e) { /* 무시 */ }
  return null;
}

function safe(fn, fallback) {
  try {
    const value = fn();
    return (value === undefined || value === null) ? fallback : value;
  } catch (e) {
    return fallback;
  }
}

function describe(element) {
  const role = safe(() => String(element.role()), '?');
  const sub = safe(() => String(element.subrole()), '');
  const name = safe(() => String(element.name()), '');
  const value = safe(() => String(element.value()), '');
  const title = safe(() => String(element.title()), '');
  const pos = safe(() => element.position(), null);
  const size = safe(() => element.size(), null);
  const where = (pos && size) ? ('@(' + pos[0] + ',' + pos[1] + ') ' + size[0] + 'x' + size[1]) : '';
  let text = role;
  if (sub) { text += '/' + sub; }
  text += ' ' + where;
  if (title) { text += "  title='" + title + "'"; }
  if (name && name !== title) { text += "  name='" + name + "'"; }
  if (value && value.length < 80) { text += "  value='" + value + "'"; }
  return text;
}

// --------------------------------------------------------------------------
// check : 쓸 수 있는 상태인지 확인
// --------------------------------------------------------------------------
function commandCheck() {
  const se = systemEvents();
  const version = safe(() => String(Application('Finder').version()), '?');
  out('[확인] macOS 시스템 이벤트 사용 가능');
  out('       Finder 버전: ' + version);

  const ax = hasAccessibility(se);
  out((ax ? '[정상] ' : '[확인 필요] ') + '손쉬운 사용(접근성) 권한: ' + (ax ? '허용됨' : '없음'));
  if (!ax) {
    out('       시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서');
    out('       터미널(또는 이 프로그램)을 켜 주세요. 권한이 없으면 아무것도 못 합니다.');
  }

  const proc = findKakaoProcess(se);
  if (!proc) {
    out('[확인 필요] 카카오톡이 실행되어 있지 않습니다.');
    return;
  }
  out('[정상] 카카오톡 찾음: ' + safe(() => String(proc.name()), '?'));

  const windows = safe(() => proc.windows(), []);
  out('       창 ' + windows.length + '개');
  for (let i = 0; i < windows.length; i++) {
    out('        - ' + describe(windows[i]));
  }
  if (windows.length === 0) {
    out('       창이 없습니다. 카카오톡 창을 열어 주세요.');
  }
}

// --------------------------------------------------------------------------
// dump : 화면 구조를 그대로 출력 (가장 중요한 단계)
// --------------------------------------------------------------------------
function commandDump(maxDepth) {
  const se = systemEvents();
  if (!hasAccessibility(se)) {
    out('손쉬운 사용 권한이 없어 화면을 읽을 수 없습니다. check 를 먼저 실행하세요.');
    return;
  }
  const proc = findKakaoProcess(se);
  if (!proc) { out('카카오톡이 실행되어 있지 않습니다.'); return; }

  const windows = safe(() => proc.windows(), []);
  out('카카오톡 창 ' + windows.length + '개 / 최대 깊이 ' + maxDepth);
  let counter = { n: 0 };
  for (let i = 0; i < windows.length; i++) {
    out('');
    out('=== 창 ' + (i + 1) + ' : ' + describe(windows[i]) + ' ===');
    walk(windows[i], 1, maxDepth, counter);
  }
  out('');
  out('요소 ' + counter.n + '개를 출력했습니다.');
}

function walk(element, depth, maxDepth, counter) {
  if (depth > maxDepth || counter.n >= MAX_DUMP_NODES) { return; }
  const children = safe(() => element.uiElements(), []);
  for (let i = 0; i < children.length; i++) {
    if (counter.n >= MAX_DUMP_NODES) {
      out('  (너무 많아 여기서 멈춥니다)');
      return;
    }
    counter.n++;
    let indent = '';
    for (let d = 0; d < depth; d++) { indent += '  '; }
    out(indent + describe(children[i]));
    walk(children[i], depth + 1, maxDepth, counter);
  }
}

// --------------------------------------------------------------------------
// rooms : 채팅방 목록 읽기
// --------------------------------------------------------------------------
// 맥 카카오톡은 목록을 표(AXTable/AXOutline)나 리스트로 내놓는 경우가 많습니다.
// 화면에 따라 다르므로 여러 형태를 모두 훑어 이름 같아 보이는 것을 모읍니다.
function collectRoomNames(root) {
  const found = [];
  const seen = {};
  const containers = [];

  function scan(element, depth) {
    if (depth > 12) { return; }
    const role = safe(() => String(element.role()), '');
    if (role === 'AXTable' || role === 'AXOutline' || role === 'AXList') {
      containers.push(element);
    }
    const children = safe(() => element.uiElements(), []);
    for (let i = 0; i < children.length; i++) { scan(children[i], depth + 1); }
  }
  scan(root, 0);

  for (let c = 0; c < containers.length; c++) {
    const rows = safe(() => containers[c].uiElements(), []);
    for (let r = 0; r < rows.length; r++) {
      const texts = [];
      collectText(rows[r], texts, 0);
      if (texts.length === 0) { continue; }
      const name = String(texts[0]).trim();
      if (!name || name.length < 2 || name.length > 60) { continue; }
      if (seen[name]) { continue; }
      seen[name] = true;
      found.push({ name: name, detail: texts.slice(1, 3).join(' | ') });
    }
  }
  return found;
}

function collectText(element, bucket, depth) {
  if (depth > 6 || bucket.length > 8) { return; }
  const value = safe(() => String(element.value()), '');
  const title = safe(() => String(element.title()), '');
  const name = safe(() => String(element.name()), '');
  const text = (value || title || name || '').trim();
  if (text && text.length < 200) { bucket.push(text); }
  const children = safe(() => element.uiElements(), []);
  for (let i = 0; i < children.length; i++) { collectText(children[i], bucket, depth + 1); }
}

function commandRooms() {
  const se = systemEvents();
  if (!hasAccessibility(se)) { out('손쉬운 사용 권한이 없습니다. check 를 먼저 실행하세요.'); return; }
  const proc = findKakaoProcess(se);
  if (!proc) { out('카카오톡이 실행되어 있지 않습니다.'); return; }
  const windows = safe(() => proc.windows(), []);
  if (windows.length === 0) { out('카카오톡 창이 없습니다.'); return; }

  const rooms = collectRoomNames(windows[0]);
  out('읽은 방 후보 ' + rooms.length + '개');
  for (let i = 0; i < rooms.length; i++) {
    out('  ' + (i + 1) + '. ' + rooms[i].name + (rooms[i].detail ? ('   [' + rooms[i].detail + ']') : ''));
  }
  if (rooms.length === 0) {
    out('');
    out('하나도 읽지 못했습니다. dump 를 실행해 실제 구조를 확인해 주세요:');
    out('  osascript -l JavaScript kakao-mac.js dump 8 > 구조.txt');
  }
}

// --------------------------------------------------------------------------
// open : 방을 찾아 열기
// --------------------------------------------------------------------------
function normalize(text) {
  return String(text).replace(/[^0-9A-Za-z가-힣]/g, '').toLowerCase();
}

function findRoomRow(root, targetName) {
  const target = normalize(targetName);
  let best = null;

  function scan(element, depth) {
    if (depth > 12 || best) { return; }
    const role = safe(() => String(element.role()), '');
    if (role === 'AXRow' || role === 'AXCell' || role === 'AXStaticText') {
      const texts = [];
      collectText(element, texts, 0);
      for (let i = 0; i < texts.length; i++) {
        if (normalize(texts[i]) === target) { best = element; return; }
      }
    }
    const children = safe(() => element.uiElements(), []);
    for (let i = 0; i < children.length; i++) { scan(children[i], depth + 1); }
  }
  scan(root, 0);
  return best;
}

function commandOpen(roomName) {
  const se = systemEvents();
  if (!hasAccessibility(se)) { out('손쉬운 사용 권한이 없습니다.'); return null; }
  const proc = findKakaoProcess(se);
  if (!proc) { out('카카오톡이 실행되어 있지 않습니다.'); return null; }

  proc.frontmost = true;
  delay(0.3);
  const windows = safe(() => proc.windows(), []);
  if (windows.length === 0) { out('카카오톡 창이 없습니다.'); return null; }

  const row = findRoomRow(windows[0], roomName);
  if (!row) {
    out("'" + roomName + "' 을(를) 목록에서 찾지 못했습니다.");
    out('rooms 로 실제 읽히는 이름을 먼저 확인해 주세요.');
    return null;
  }
  // 행을 두 번 눌러 방을 엽니다.
  const ok = safe(() => { row.actions['AXPress'].perform(); return true; }, false);
  if (!ok) {
    safe(() => { row.select(); return true; }, false);
  }
  delay(0.8);
  out("'" + roomName + "' 을(를) 열었습니다.");
  return proc;
}

// --------------------------------------------------------------------------
// send : 보내기 (기본은 확인만, --live 를 붙여야 실제 전송)
// --------------------------------------------------------------------------
function findTextInput(root) {
  let best = null;
  let bestY = -1;
  function scan(element, depth) {
    if (depth > 12) { return; }
    const role = safe(() => String(element.role()), '');
    if (role === 'AXTextArea' || role === 'AXTextField') {
      const pos = safe(() => element.position(), null);
      const size = safe(() => element.size(), null);
      if (pos && size && size[0] > 80) {
        if (pos[1] > bestY) { bestY = pos[1]; best = element; }
      }
    }
    const children = safe(() => element.uiElements(), []);
    for (let i = 0; i < children.length; i++) { scan(children[i], depth + 1); }
  }
  scan(root, 0);
  return best;
}

function commandSend(roomName, message, live) {
  const proc = commandOpen(roomName);
  if (!proc) { return; }

  const windows = safe(() => proc.windows(), []);
  let input = null;
  for (let i = 0; i < windows.length && !input; i++) {
    input = findTextInput(windows[i]);
  }
  if (!input) {
    out('글 입력칸을 찾지 못했습니다. 전송하지 않았습니다.');
    out('dump 로 입력칸의 실제 역할(role)을 확인해 주세요.');
    return;
  }
  out('입력칸을 찾았습니다: ' + describe(input));

  // 글을 넣고, 실제로 들어갔는지 되읽어 확인합니다.
  const wrote = safe(() => { input.value = message; return true; }, false);
  if (!wrote) { out('글을 입력칸에 넣지 못했습니다. 전송하지 않았습니다.'); return; }
  delay(0.3);
  const back = safe(() => String(input.value()), '');
  out("입력칸 확인: '" + back + "'");

  if (normalize(back) !== normalize(message)) {
    out('입력칸 내용이 보낼 글과 다릅니다. 안전을 위해 전송하지 않습니다.');
    safe(() => { input.value = ''; return true; }, false);
    return;
  }

  if (!live) {
    out('');
    out('여기까지가 확인 모드입니다. 실제로는 보내지 않았습니다.');
    out('입력칸을 비웁니다. 실제로 보내려면 끝에 --live 를 붙이세요.');
    safe(() => { input.value = ''; return true; }, false);
    return;
  }

  const se = systemEvents();
  se.keyCode(36); // Return
  delay(0.8);
  const after = safe(() => String(input.value()), '');
  if (after.trim() === '') {
    out('전송한 것으로 보입니다. (입력칸이 비워졌습니다)');
  } else {
    out('전송되지 않은 것 같습니다. 입력칸에 글이 남아 있습니다: ' + after);
    out('입력칸을 비웁니다.');
    safe(() => { input.value = ''; return true; }, false);
  }
}

// --------------------------------------------------------------------------
function run(argv) {
  const command = (argv.length > 0) ? String(argv[0]) : 'check';
  if (command === 'check') { commandCheck(); return; }
  if (command === 'dump') {
    const depth = (argv.length > 1) ? parseInt(argv[1], 10) : 6;
    commandDump(isNaN(depth) ? 6 : depth);
    return;
  }
  if (command === 'rooms') { commandRooms(); return; }
  if (command === 'open') {
    if (argv.length < 2) { out('사용법: open "방이름"'); return; }
    commandOpen(String(argv[1]));
    return;
  }
  if (command === 'send') {
    if (argv.length < 3) { out('사용법: send "방이름" "보낼 글" [--live]'); return; }
    let live = false;
    for (let i = 3; i < argv.length; i++) {
      if (String(argv[i]) === '--live') { live = true; }
    }
    commandSend(String(argv[1]), String(argv[2]), live);
    return;
  }
  out('모르는 명령입니다: ' + command);
  out('쓸 수 있는 명령: check / dump / rooms / open / send');
}
