package main

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"

	_ "github.com/go-sql-driver/mysql"
)

var db *sql.DB

type Todo struct {
	ID        int    `json:"id"`
	Title     string `json:"title"`
	Completed bool   `json:"completed"`
	CreatedAt string `json:"created_at"`
}

type TodoRaw struct {
	ID        int    `json:"id"`
	Title     string `json:"title"`
	Completed int    `json:"completed"`
	CreatedAt string `json:"created_at"`
}

func loadEnv() map[string]string {
	vars := make(map[string]string)
	f, err := os.Open(".env")
	if err != nil {
		return vars
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "#") || line == "" {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			vars[strings.TrimSpace(parts[0])] = strings.Trim(strings.TrimSpace(parts[1]), "\"'")
		}
	}
	return vars
}

func initDB() {
	env := loadEnv()
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?parseTime=true",
		getEnv(env, "DB_USER", "root"),
		getEnv(env, "DB_PASS", ""),
		getEnv(env, "DB_HOST", "localhost"),
		getEnv(env, "DB_NAME", "testgo_todo"),
	)
	var err error
	db, err = sql.Open("mysql", dsn)
	if err != nil {
		fmt.Println("DB open error:", err)
		os.Exit(1)
	}
	if err = db.Ping(); err != nil {
		fmt.Println("DB ping error:", err)
		os.Exit(1)
	}
	db.Exec(`CREATE TABLE IF NOT EXISTS todos (
		id INT AUTO_INCREMENT PRIMARY KEY,
		title VARCHAR(255) NOT NULL,
		completed TINYINT(1) DEFAULT 0,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
	)`)
	fmt.Println("DB connected")
}

func getEnv(env map[string]string, key, fallback string) string {
	if v, ok := env[key]; ok {
		return v
	}
	return fallback
}

func jsonResp(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func uiHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(htmlUI))
}

func listTodos(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT id, title, completed, created_at FROM todos ORDER BY created_at DESC")
	if err != nil {
		jsonResp(w, 500, map[string]string{"error": err.Error()})
		return
	}
	defer rows.Close()
	var todos []TodoRaw
	for rows.Next() {
		var t TodoRaw
		rows.Scan(&t.ID, &t.Title, &t.Completed, &t.CreatedAt)
		todos = append(todos, t)
	}
	if todos == nil {
		todos = []TodoRaw{}
	}
	jsonResp(w, 200, map[string]interface{}{"status": "ok", "data": todos})
}

func createTodo(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Title string `json:"title"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	title := strings.TrimSpace(body.Title)
	if title == "" {
		jsonResp(w, 400, map[string]string{"status": "error", "message": "title is required"})
		return
	}
	result, err := db.Exec("INSERT INTO todos (title) VALUES (?)", title)
	if err != nil {
		jsonResp(w, 500, map[string]string{"error": err.Error()})
		return
	}
	id, _ := result.LastInsertId()
	jsonResp(w, 201, map[string]interface{}{"status": "ok", "data": map[string]interface{}{"id": id, "title": title, "completed": false}})
}

func updateTodo(w http.ResponseWriter, r *http.Request, id int) {
	var body struct {
		Title     *string `json:"title"`
		Completed *bool   `json:"completed"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if body.Title != nil && body.Completed != nil {
		completed := 0
		if *body.Completed {
			completed = 1
		}
		db.Exec("UPDATE todos SET title = ?, completed = ? WHERE id = ?", *body.Title, completed, id)
	} else if body.Completed != nil {
		completed := 0
		if *body.Completed {
			completed = 1
		}
		db.Exec("UPDATE todos SET completed = ? WHERE id = ?", completed, id)
	} else if body.Title != nil {
		db.Exec("UPDATE todos SET title = ? WHERE id = ?", *body.Title, id)
	}
	jsonResp(w, 200, map[string]string{"status": "ok", "message": "updated"})
}

func deleteTodo(w http.ResponseWriter, r *http.Request, id int) {
	db.Exec("DELETE FROM todos WHERE id = ?", id)
	jsonResp(w, 200, map[string]string{"status": "ok", "message": "deleted"})
}

func todosHandler(w http.ResponseWriter, r *http.Request) {
	re := regexp.MustCompile(`^/todos/(\d+)$`)
	switch r.Method {
	case http.MethodPost:
		createTodo(w, r)
		return
	case http.MethodGet:
		if r.URL.Path == "/todos" {
			listTodos(w, r)
			return
		}
	}
	matches := re.FindStringSubmatch(r.URL.Path)
	if len(matches) == 2 {
		id, _ := strconv.Atoi(matches[1])
		switch r.Method {
		case http.MethodPut:
			updateTodo(w, r, id)
			return
		case http.MethodDelete:
			deleteTodo(w, r, id)
			return
		}
	}
	jsonResp(w, 404, map[string]string{"status": "error", "message": "not found"})
}

func main() {
	initDB()
	env := loadEnv()
	port := getEnv(env, "PORT", "4100")

	http.HandleFunc("/", uiHandler)
	http.HandleFunc("/todos", todosHandler)
	http.HandleFunc("/todos/", todosHandler)

	fmt.Printf("Go todo app listening on port %s\n", port)
	http.ListenAndServe("127.0.0.1:"+port, nil)
}

const htmlUI = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Todo App - Go</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 16px;background:#f5f5f5;color:#333}
h1{margin-bottom:20px;color:#00add8}
.add-form{display:flex;gap:8px;margin-bottom:20px}
.add-form input{flex:1;padding:10px 14px;border:1px solid #ddd;border-radius:6px;font-size:15px;outline:none}
.add-form input:focus{border-color:#00add8}
.add-form button{padding:10px 20px;background:#00add8;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:15px}
.add-form button:hover{background:#0097b8}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}
th{background:#00add8;color:#fff;padding:12px;text-align:left;font-weight:500}
td{padding:10px 12px;border-top:1px solid #eee}
tr:hover td{background:#e8f7fc}
.done{text-decoration:line-through;color:#999}
.btn{padding:5px 12px;border:none;border-radius:4px;cursor:pointer;font-size:13px;margin-right:4px}
.btn-edit{background:#f59e0b;color:#fff}.btn-edit:hover{background:#d97706}
.btn-del{background:#ef4444;color:#fff}.btn-del:hover{background:#dc2626}
.btn-toggle{background:#10b981;color:#fff}.btn-toggle:hover{background:#059669}
.edit-input{padding:6px 10px;border:1px solid #ddd;border-radius:4px;font-size:14px;width:100%}
.empty{text-align:center;padding:30px;color:#999}
</style></head><body>
<h1>🐘 Go Todo App</h1>
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
</script></body></html>`
