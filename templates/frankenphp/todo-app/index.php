<?php
// --- Load .env ---
function loadEnv() {
    $env = [];
    $envFile = __DIR__ . '/.env';
    if (!file_exists($envFile)) return $env;
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line[0] === '#' || !str_contains($line, '=')) continue;
        [$k, $v] = explode('=', $line, 2);
        $env[trim($k)] = trim($v, " \t\n\r\0\x0B\"'");
    }
    return $env;
}

function env(array $env, string $key, string $default = ''): string {
    return $env[$key] ?? $default;
}

// --- DB ---
function getDb(array $env): PDO {
    static $pdo = null;
    if ($pdo) return $pdo;
    $pdo = new PDO(
        sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4;unix_socket=/run/mysqld/mysqld.sock', env($env, 'DB_HOST', 'localhost'), env($env, 'DB_NAME', 'testfranken_todo')),
        env($env, 'DB_USER', 'root'),
        env($env, 'DB_PASS', '')
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    return $pdo;
}

function initDb(PDO $db) {
    $db->exec('CREATE TABLE IF NOT EXISTS todos (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        completed TINYINT(1) DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )');
}

// --- Helpers ---
function jsonResponse(int $status, array $data): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}

function readBody(): array {
    $raw = file_get_contents('php://input');
    return json_decode($raw, true) ?? [];
}

function htmlResponse(string $html): void {
    http_response_code(200);
    header('Content-Type: text/html; charset=utf-8');
    echo $html;
    exit;
}

// --- HTML UI ---
$HTML_UI = <<<'HTML'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Todo App - FrankenPHP</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 16px;background:#f5f5f5;color:#333}
h1{margin-bottom:20px;color:#7c3aed}
.add-form{display:flex;gap:8px;margin-bottom:20px}
.add-form input{flex:1;padding:10px 14px;border:1px solid #ddd;border-radius:6px;font-size:15px;outline:none}
.add-form input:focus{border-color:#7c3aed}
.add-form button{padding:10px 20px;background:#7c3aed;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:15px}
.add-form button:hover{background:#6d28d9}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}
th{background:#7c3aed;color:#fff;padding:12px;text-align:left;font-weight:500}
td{padding:10px 12px;border-top:1px solid #eee}
tr:hover td{background:#f3eefe}
.done{text-decoration:line-through;color:#999}
.btn{padding:5px 12px;border:none;border-radius:4px;cursor:pointer;font-size:13px;margin-right:4px}
.btn-edit{background:#f59e0b;color:#fff}.btn-edit:hover{background:#d97706}
.btn-del{background:#ef4444;color:#fff}.btn-del:hover{background:#dc2626}
.btn-toggle{background:#10b981;color:#fff}.btn-toggle:hover{background:#059669}
.edit-input{padding:6px 10px;border:1px solid #ddd;border-radius:4px;font-size:14px;width:100%}
.empty{text-align:center;padding:30px;color:#999}
</style></head><body>
<h1>⚡ FrankenPHP Todo App</h1>
<div class="add-form">
<input id="titleInput" placeholder="Tambah todo baru..." onkeydown="if(event.key==='Enter')addTodo()">
<button onclick="addTodo()">Tambah</button>
</div>
<table><thead><tr><th style="width:40px">ID</th><th>Title</th><th style="width:80px">Status</th><th style="width:120px">Tanggal</th><th style="width:160px">Aksi</th></tr></thead>
<tbody id="tbody"></tbody></table>
<script>
async function api(method,path,body){
const o={method,headers:{'Content-Type':'application/json'}};
if(body)o.body=JSON.stringify(body);
const r=await fetch(path,o);
return r.json();
}
function fmt(d){return new Date(d).toLocaleDateString('id-ID',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'})}
function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}
async function load(){
const r=await api('GET','/todos');
const tb=document.getElementById('tbody');
if(!r.data||!r.data.length){tb.innerHTML='<tr><td colspan="5" class="empty">Belum ada todo</td></tr>';return}
tb.innerHTML=r.data.map(t=>'<tr id="row-'+t.id+'">'+
'<td>'+t.id+'</td>'+
'<td id="title-'+t.id+'" class="'+(t.completed?'done':'')+'">'+esc(t.title)+'</td>'+
'<td>'+(t.completed?'&#x2705; Selesai':'&#x23F3; Proses')+'</td>'+
'<td>'+fmt(t.created_at)+'</td>'+
'<td>'+
'<button class="btn btn-toggle" onclick="toggle('+t.id+','+t.completed+')">'+(t.completed?'Undo':'Done')+'</button>'+
'<button class="btn btn-edit" onclick="edit('+t.id+')">Edit</button>'+
'<button class="btn btn-del" onclick="del('+t.id+')">Hapus</button>'+
'</td></tr>').join('');
}
async function addTodo(){
const inp=document.getElementById('titleInput');
const title=inp.value.trim();if(!title)return;
await api('POST','/todos',{title});inp.value='';load();
}
async function toggle(id,completed){
await api('PUT','/todos/'+id,{completed:!completed});load();
}
function edit(id){
const td=document.getElementById('title-'+id);
const cur=td.textContent;
td.innerHTML='<input class="edit-input" value="'+esc(cur)+'" onkeydown="if(event.key===&quot;Enter&quot;)saveEdit('+id+',this)" onblur="load()">';
td.querySelector('input').focus();
}
async function saveEdit(id,inp){
const title=inp.value.trim();if(!title){load();return}
await api('PUT','/todos/'+id,{title,completed:false});load();
}
async function del(id){
if(!confirm('Hapus todo #'+id+'?'))return;
await api('DELETE','/todos/'+id);load();
}
load();
</script></body></html>
HTML;

// --- Router ---
$env = loadEnv();
$db = getDb($env);
initDb($db);

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

// UI
if ($uri === '/' || $uri === '/ui') {
    htmlResponse($HTML_UI);
}

// GET /todos
if ($uri === '/todos' && $method === 'GET') {
    $stmt = $db->query('SELECT * FROM todos ORDER BY created_at DESC');
    jsonResponse(200, ['status' => 'ok', 'data' => $stmt->fetchAll()]);
}

// POST /todos
if ($uri === '/todos' && $method === 'POST') {
    $body = readBody();
    $title = trim($body['title'] ?? '');
    if ($title === '') jsonResponse(400, ['status' => 'error', 'message' => 'title is required']);
    $stmt = $db->prepare('INSERT INTO todos (title) VALUES (?)');
    $stmt->execute([$title]);
    jsonResponse(201, ['status' => 'ok', 'data' => ['id' => (int)$db->lastInsertId(), 'title' => $title, 'completed' => false]]);
}

// PUT /todos/:id
if (preg_match('#^/todos/(\d+)$#', $uri, $m) && $method === 'PUT') {
    $id = (int)$m[1];
    $body = readBody();
    $completed = !empty($body['completed']) ? 1 : 0;
    $title = isset($body['title']) ? trim($body['title']) : null;
    if ($title !== null && $title !== '') {
        $db->prepare('UPDATE todos SET title = ?, completed = ? WHERE id = ?')->execute([$title, $completed, $id]);
    } else {
        $db->prepare('UPDATE todos SET completed = ? WHERE id = ?')->execute([$completed, $id]);
    }
    jsonResponse(200, ['status' => 'ok', 'message' => 'updated']);
}

// DELETE /todos/:id
if (preg_match('#^/todos/(\d+)$#', $uri, $m) && $method === 'DELETE') {
    $id = (int)$m[1];
    $db->prepare('DELETE FROM todos WHERE id = ?')->execute([$id]);
    jsonResponse(200, ['status' => 'ok', 'message' => 'deleted']);
}

jsonResponse(404, ['status' => 'error', 'message' => 'not found']);
