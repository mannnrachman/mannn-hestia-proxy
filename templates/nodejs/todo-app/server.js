const http = require('http');
const url = require('url');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

// --- Read .env manually (no dotenv dependency) ---
function loadEnv() {
    const envPath = path.join(__dirname, '.env');
    const vars = {};
    try {
        const data = fs.readFileSync(envPath, 'utf8');
        for (const line of data.split('\n')) {
            const m = line.match(/^([A-Z_]+)=(.+)$/);
            if (m) vars[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
        }
    } catch {}
    return vars;
}

const env = loadEnv();
const PORT = parseInt(env.PORT) || 3100;
const DB_CONFIG = {
    host: env.DB_HOST || 'localhost',
    user: env.DB_USER || 'root',
    password: env.DB_PASS || '',
    database: env.DB_NAME || 'testnode_todo',
};

let pool;
let dbReady = false;

async function initDB() {
    pool = mysql.createPool({ ...DB_CONFIG, waitForConnections: true, connectionLimit: 5 });
    await pool.execute(`
        CREATE TABLE IF NOT EXISTS todos (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            completed TINYINT(1) DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
    dbReady = true;
    console.log('DB connected');
}

async function initDBWithRetry() {
    const MAX_RETRIES = 10;
    const INITIAL_DELAY = 2000;
    const MAX_DELAY = 60000;
    let delay = INITIAL_DELAY;

    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        try {
            await initDB();
            return;
        } catch (err) {
            console.error(`DB init attempt ${attempt}/${MAX_RETRIES} failed: ${err.message}`);
            if (attempt < MAX_RETRIES) {
                console.log(`Retrying in ${delay / 1000}s...`);
                await new Promise((resolve) => setTimeout(resolve, delay));
                delay = Math.min(delay * 2, MAX_DELAY);
            }
        }
    }
    console.error('All DB connection attempts failed. App starting in degraded mode.');
}

function json(res, status, data) {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
}

function readBody(req) {
    return new Promise((resolve) => {
        let body = '';
        req.on('data', (c) => (body += c));
        req.on('end', () => resolve(body));
    });
}

const HTML_UI = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Todo App - Node.js</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 16px;background:#f5f5f5;color:#333}
h1{margin-bottom:20px;color:#1a1a2e}
.add-form{display:flex;gap:8px;margin-bottom:20px}
.add-form input{flex:1;padding:10px 14px;border:1px solid #ddd;border-radius:6px;font-size:15px;outline:none}
.add-form input:focus{border-color:#4361ee}
.add-form button{padding:10px 20px;background:#4361ee;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:15px}
.add-form button:hover{background:#3a56d4}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}
th{background:#1a1a2e;color:#fff;padding:12px;text-align:left;font-weight:500}
td{padding:10px 12px;border-top:1px solid #eee}
tr:hover td{background:#f0f4ff}
.done{text-decoration:line-through;color:#999}
.btn{padding:5px 12px;border:none;border-radius:4px;cursor:pointer;font-size:13px;margin-right:4px}
.btn-edit{background:#f59e0b;color:#fff}.btn-edit:hover{background:#d97706}
.btn-del{background:#ef4444;color:#fff}.btn-del:hover{background:#dc2626}
.btn-toggle{background:#10b981;color:#fff}.btn-toggle:hover{background:#059669}
.edit-input{padding:6px 10px;border:1px solid #ddd;border-radius:4px;font-size:14px;width:100%}
.empty{text-align:center;padding:30px;color:#999}
</style></head><body>
<h1>📝 Node.js Todo App</h1>
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
'<td>'+(t.completed?'✅ Selesai':'⏳ Proses')+'</td>'+
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
</script></body></html>`;

async function handler(req, res) {
    const parsed = url.parse(req.url, true);
    const route = parsed.pathname;
    const method = req.method;

    // UI
    if ((route === '/' || route === '/ui') && method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(HTML_UI);
        return;
    }

    // DB-dependent routes — reject if DB unavailable
    if (!dbReady && route.startsWith('/todos')) {
        return json(res, 503, { status: 'error', message: 'database unavailable' });
    }

    // GET /todos
    if (route === '/todos' && method === 'GET') {
        const [rows] = await pool.execute('SELECT * FROM todos ORDER BY created_at DESC');
        return json(res, 200, { status: 'ok', data: rows });
    }

    // POST /todos
    if (route === '/todos' && method === 'POST') {
        const body = JSON.parse(await readBody(req));
        const title = (body.title || '').trim();
        if (!title) return json(res, 400, { status: 'error', message: 'title is required' });
        const [result] = await pool.execute('INSERT INTO todos (title) VALUES (?)', [title]);
        return json(res, 201, { status: 'ok', data: { id: result.insertId, title, completed: false } });
    }

    // PUT /todos/:id
    const putMatch = route.match(/^\/todos\/(\d+)$/);
    if (putMatch && method === 'PUT') {
        const id = putMatch[1];
        const body = JSON.parse(await readBody(req));
        const completed = body.completed ? 1 : 0;
        const title = body.title ? body.title.trim() : null;
        if (title !== null) {
            await pool.execute('UPDATE todos SET title = ?, completed = ? WHERE id = ?', [title, completed, id]);
        } else {
            await pool.execute('UPDATE todos SET completed = ? WHERE id = ?', [completed, id]);
        }
        return json(res, 200, { status: 'ok', message: 'updated' });
    }

    // DELETE /todos/:id
    const delMatch = route.match(/^\/todos\/(\d+)$/);
    if (delMatch && method === 'DELETE') {
        await pool.execute('DELETE FROM todos WHERE id = ?', [delMatch[1]]);
        return json(res, 200, { status: 'ok', message: 'deleted' });
    }

    json(res, 404, { status: 'error', message: 'not found' });
}

http.createServer(handler).listen(PORT, '127.0.0.1', () => {
    console.log('Todo app listening on port ' + PORT);
});

initDBWithRetry().catch((err) => {
    console.error('DB init failed:', err.message);
});
