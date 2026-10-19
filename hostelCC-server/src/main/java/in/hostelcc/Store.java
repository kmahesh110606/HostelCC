package in.hostelcc;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
import java.util.*;
import java.time.Instant;

@Component
public class Store {
    final JdbcTemplate jdbc;
    public Store(JdbcTemplate jdbc) { this.jdbc=jdbc; }
    public static String id() { return UUID.randomUUID().toString(); }
    public static String now() { return Instant.now().toString(); }
    public List<Map<String,Object>> list(String sql,Object... args) {
        return jdbc.query(sql,(rs,n)->readRow(rs),args);
    }
    static Map<String,Object> readRow(java.sql.ResultSet rs) throws java.sql.SQLException {
            var row=new LinkedHashMap<String,Object>();
            for(int i=1;i<=rs.getMetaData().getColumnCount();i++) {
                String key=rs.getMetaData().getColumnLabel(i).toLowerCase(Locale.ROOT);
                if(key.equals("weekday")) key="day";
                var parts=key.split("_"); var camel=new StringBuilder(parts[0]);
                for(int p=1;p<parts.length;p++) camel.append(Character.toUpperCase(parts[p].charAt(0))).append(parts[p].substring(1));
                row.put(camel.toString(),rs.getObject(i));
            }
            return row;
    }
    public Map<String,Object> one(String sql,Object... args) {
        var rows=list(sql,args); if(rows.isEmpty()) throw error(404,"Record not found"); return rows.getFirst();
    }
    public long count(String sql,Object... args) { return jdbc.queryForObject(sql,Long.class,args); }
    public int exec(String sql,Object... args) { return jdbc.update(sql,args); }
    public void audit(Actor a,String action,String type,String id,String block,String detail) {
        exec("INSERT INTO audit(id,actor_id,action,resource_type,resource_id,block_id,detail,created_at) VALUES (?,?,?,?,?,?,?,?)",id(),a.id(),action,type,id,block,detail,now());
    }
    public static ResponseStatusException error(int status,String message) { return new ResponseStatusException(HttpStatus.valueOf(status),message); }
    public static String str(Map<String,Object> m,String key) { Object v=m.get(key); return v==null?"":v.toString(); }
    public static String required(Map<String,Object> m,String key,int max) {
        String s=str(m,key).strip(); if(s.isEmpty() || s.length()>max) throw error(400,key+" is required (maximum "+max+" characters)"); return s;
    }
    public static String optional(Map<String,Object> m,String key,int max) {
        String s=str(m,key).strip(); if(s.length()>max) throw error(400,key+" is too long"); return s;
    }
    public static boolean bool(Map<String,Object> m,String key) { return Boolean.TRUE.equals(m.get(key)); }
    public static int integer(Map<String,Object> m,String key,int min,int max) {
        try { int v=Integer.parseInt(str(m,key)); if(v<min||v>max) throw new NumberFormatException(); return v; }
        catch(NumberFormatException e) { throw error(400,key+" must be between "+min+" and "+max); }
    }
    public static String choice(Map<String,Object> m,String key,String... options) {
        String s=required(m,key,100); if(!List.of(options).contains(s)) throw error(400,"Invalid "+key); return s;
    }
    public static String instant(Map<String,Object> m,String key) {
        try { return Instant.parse(required(m,key,40)).toString(); } catch(java.time.DateTimeException e) { throw error(400,"Invalid "+key+" timestamp"); }
    }
}
