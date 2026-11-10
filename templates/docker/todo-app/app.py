import json
import re
import os
import datetime
import pymysql
from http.server import HTTPServer, BaseHTTPRequestHandler

class JsonEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, (datetime.date, datetime.datetime)):
            return o.isoformat()
        return super().default(o)

def load_env():
    env = {}
    try:
        with open('.env') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    env[k.strip()] = v.strip().strip('"').strip("'")
    except:
        pass
    return env

env = load_env()
PORT = int(env.get('PORT', 9100))
DB_CONFIG = {
    'host': env.get('DB_HOST', 'host.docker.internal'),
    'user': env.get('DB_USER', 'root'),
    'password': env.get('DB_PASS', ''),
    'database': env.get('DB_NAME', 'testdocker_todo'),
    'cursorclass': pymysql.cursors.DictCursor,
}

def get_db():
    return pymysql.connect(**DB_CONFIG)

def init_db():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute('''CREATE TABLE IF NOT EXISTS todos (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            completed TINYINT(1) DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )''')
    conn.commit()
    conn.close()
    print('DB connected')

HTML_UI = '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Todo App - Docker Python</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 16px;background:#f5f5f5;color:#333}
h1{margin-bottom:20px;color:#2496ed}
.add-form{display:flex;gap:8px;margin-bottom:20px}
.add-form input{flex:1;padding:10px 14px;border:1px solid #ddd;border-radius:6px;font-size:15px;outline:none}
.add-form input:focus{border-color:#2496ed}
.add-form button{padding:10px 20px;background:#2496ed;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:15px}
.add-form button:hover{background:#1a7fd4}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}
th{background:#2496ed;color:#fff;padding:12px;text-align:left;font-weight:500}
td{padding:10px 12px;border-top:1px solid #eee}
tr:hover td{background:#e3f2fd}
.done{text-decoration:line-through;color:#999}
.btn{padding:5px 12px;border:none;border-radius:4px;cursor:pointer;font-size:13px;margin-right:4px}
.btn-edit{background:#f59e0b;color:#fff}.btn-edit:hover{background:#d97706}
.btn-del{background:#ef4444;color:#fff}.btn-del:hover{background:#dc2626}
.btn-toggle{background:#10b981;color:#fff}.btn-toggle:hover{background:#059669}
.edit-input{padding:6px 10px;border:1px solid #ddd;border-radius:4px;font-size:14px;width:100%}
.empty{text-align:center;padding:30px;color:#999}
</style></head><body>
<h1>🐳 Docker Python Todo App</h1>
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
</script></body></html>'''

class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, data):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data, cls=JsonEncoder).encode())

    def read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        return json.loads(self.rfile.read(length)) if length else {}

    def do_GET(self):
        if self.path == '/' or self.path == '/ui':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_UI.encode())
            return
        if self.path == '/todos':
            conn = get_db()
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM todos ORDER BY created_at DESC')
                rows = cur.fetchall()
            conn.close()
            self.send_json(200, {'status': 'ok', 'data': rows})
            return
        self.send_json(404, {'status': 'error', 'message': 'not found'})

    def do_POST(self):
        if self.path == '/todos':
            body = self.read_body()
            title = (body.get('title') or '').strip()
            if not title:
                self.send_json(400, {'status': 'error', 'message': 'title is required'})
                return
            conn = get_db()
            with conn.cursor() as cur:
                cur.execute('INSERT INTO todos (title) VALUES (%s)', (title,))
                conn.commit()
                uid = cur.lastrowid
            conn.close()
            self.send_json(201, {'status': 'ok', 'data': {'id': uid, 'title': title, 'completed': False}})
            return
        self.send_json(404, {'status': 'error', 'message': 'not found'})

    def do_PUT(self):
        m = re.match(r'^/todos/(\d+)$', self.path)
        if m:
            uid = int(m.group(1))
            body = self.read_body()
            completed = 1 if body.get('completed') else 0
            title = (body.get('title') or '').strip() or None
            conn = get_db()
            with conn.cursor() as cur:
                if title:
                    cur.execute('UPDATE todos SET title=%s, completed=%s WHERE id=%s', (title, completed, uid))
                else:
                    cur.execute('UPDATE todos SET completed=%s WHERE id=%s', (completed, uid))
                conn.commit()
            conn.close()
            self.send_json(200, {'status': 'ok', 'message': 'updated'})
            return
        self.send_json(404, {'status': 'error', 'message': 'not found'})

    def do_DELETE(self):
        m = re.match(r'^/todos/(\d+)$', self.path)
        if m:
            uid = int(m.group(1))
            conn = get_db()
            with conn.cursor() as cur:
                cur.execute('DELETE FROM todos WHERE id=%s', (uid,))
                conn.commit()
            conn.close()
            self.send_json(200, {'status': 'ok', 'message': 'deleted'})
            return
        self.send_json(404, {'status': 'error', 'message': 'not found'})

    def log_message(self, format, *args):
        print(f'{self.client_address[0]} - {args[0]}')

if __name__ == '__main__':
    init_db()
    server = HTTPServer(('0.0.0.0', PORT), Handler)
    print(f'Docker Python todo app listening on port {PORT}')
    server.serve_forever()
