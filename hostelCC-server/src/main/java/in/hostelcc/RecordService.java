package in.hostelcc;

import java.time.Instant;
import java.util.*;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

/** All record pages are scoped and limited in SQL, before materialization. */
@Service
public class RecordService {
    final Store db;
    final NamedParameterJdbcTemplate sql;
    public RecordService(Store db) { this.db=db; sql=new NamedParameterJdbcTemplate(db.jdbc); }
    record Query(String select,String from,String where,String order,List<String> search) {}
    String grant(String book,String column) {
        return "EXISTS (SELECT 1 FROM duty_scopes g WHERE g.user_id=:uid AND g.active=true AND g.book='"+book+"' AND g.target_id="+column+")";
    }
    String duty(Actor a,String book,String column) { return a.global()?"true":grant(book,column); }
    String person(Actor a,String book) { return a.global()?"true":a.is("STUDENT")?"t.student_id=:uid":grant(book,"t.block_id"); }
    String mess(Actor a,String column) {
        if(a.global()) return "true";
        if(a.is("STUDENT")) return column+"=:mess";
        return "("+grant("MESS",column)+" OR EXISTS (SELECT 1 FROM mess_blocks mb WHERE mb.mess_id="+column+" AND "+grant("HOSTEL","mb.block_id")+"))";
    }
    Map<String,Object> params(Actor a) {
        var p=new HashMap<String,Object>(); p.put("uid",a.id());p.put("role",a.role());p.put("block",a.blockId());p.put("mess",a.messId());
        p.put("blocks",a.blocks().isEmpty()?List.of(""):a.blocks());p.put("now",now()); return p;
    }
    Query query(Actor a,String resource) {
        String select="t.*",from,where,order="t.id"; List<String> search=List.of();
        switch(resource) {
            case "blocks" -> { from="blocks t"; where=a.global()?"true":"t.id IN (:blocks)";order="t.name,t.id";search=List.of("t.name"); }
            case "rooms" -> { from="rooms t JOIN blocks b ON b.id=t.block_id";select+=",b.name AS block_name,(SELECT count(*) FROM users u WHERE u.room_id=t.id AND u.active=true) AS occupied";where=duty(a,"HOSTEL","t.block_id");order="b.name,t.number,t.id";search=List.of("b.name","t.number","t.room_type"); }
            case "users" -> {
                from="users t LEFT JOIN blocks b ON b.id=t.block_id LEFT JOIN rooms r ON r.id=t.room_id LEFT JOIN messes m ON m.id=t.mess_id";
                select+=",b.name AS block_name,r.number AS room_number,m.name AS mess_name";
                where=a.global()?"true":"((t.role='STUDENT' AND ("+grant("HOSTEL","t.block_id")+" OR "+grant("OUTINGS","t.block_id")+" OR "+grant("DISCIPLINE","t.block_id")+")) OR (t.role='HOUSEKEEPING' AND :role<>'HOUSEKEEPING' AND EXISTS (SELECT 1 FROM duty_scopes h WHERE h.user_id=t.id AND h.active=true AND h.book='MAINTENANCE' AND "+grant("MAINTENANCE","h.target_id")+")))";
                order="t.name,t.id";search=List.of("t.name","t.email","t.roll_no","t.role","b.name","r.number");
            }
            case "messes" -> { from="messes t";select+=",(SELECT count(*) FROM users u WHERE u.mess_id=t.id AND u.active=true AND u.role='STUDENT') AS occupied";where=mess(a,"t.id")+(a.is("STUDENT")?" OR EXISTS (SELECT 1 FROM mess_blocks mb WHERE mb.mess_id=t.id AND mb.block_id=:block)":"");order="t.name,t.id";search=List.of("t.name"); }
            case "menus" -> { from="menus t JOIN messes m ON m.id=t.mess_id";select+=",m.name AS mess_name";where=mess(a,"t.mess_id");order="m.name,CASE t.weekday WHEN 'MON' THEN 1 WHEN 'TUE' THEN 2 WHEN 'WED' THEN 3 WHEN 'THU' THEN 4 WHEN 'FRI' THEN 5 WHEN 'SAT' THEN 6 ELSE 7 END,t.id";search=List.of("m.name","t.weekday","t.breakfast","t.lunch","t.dinner"); }
            case "feedback" -> { from="feedback t JOIN users u ON u.id=t.student_id JOIN blocks b ON b.id=t.block_id JOIN messes m ON m.id=t.mess_id";select+=",u.name AS student_name,b.name AS block_name,m.name AS mess_name";where="("+person(a,"HOSTEL")+" OR "+grant("MESS","t.mess_id")+")";order="t.created_at DESC,t.id";search=List.of("u.name","m.name","t.comment","t.reply","t.meal_date"); }
            case "polls" -> { from="polls t JOIN messes m ON m.id=t.mess_id";select+=",m.name AS mess_name";where=mess(a,"t.mess_id");order="t.created_at DESC,t.id";search=List.of("t.title","m.name"); }
            case "outings","discipline","messChanges","cloakroom" -> {
                String table=resource.equals("messChanges")?"mess_changes":resource;
                from=table+" t JOIN users u ON u.id=t.student_id JOIN blocks b ON b.id=t.block_id";
                select+=",u.name AS student_name,u.roll_no,b.name AS block_name";
                where=person(a,resource.equals("outings")?"OUTINGS":resource.equals("discipline")?"DISCIPLINE":"HOSTEL");
                order="t.created_at DESC,t.id";
                search=new ArrayList<>(List.of("u.name","u.roll_no","b.name"));
                if(resource.equals("cloakroom")) { from+=" JOIN storage_rooms s ON s.id=t.storage_id LEFT JOIN storage_rooms origin ON origin.id=t.token_room_id";select+=",s.name AS storage_name,origin.name AS token_room_name";where=a.global()?"true":a.is("STUDENT")?"t.student_id=:uid":grant("CLOAKROOM","t.storage_id");order="t.submitted_at DESC,t.id";search.addAll(List.of("s.name","t.item","t.status","CAST(t.token_number AS varchar)")); }
                if(resource.equals("messChanges")) { from+=" JOIN messes m ON m.id=t.mess_id";select+=",m.name AS mess_name";search.add("m.name"); }
                if(resource.equals("outings")) search.addAll(List.of("t.destination","t.status","t.kind"));
                if(resource.equals("discipline")) search.addAll(List.of("t.violation","t.action_taken"));
            }
            case "storageRooms" -> { from="storage_rooms t JOIN blocks b ON b.id=t.block_id";select+=",b.name AS block_name,(SELECT count(*) FROM cloakroom c WHERE c.storage_id=t.id AND c.status='STORED') AS occupied";where=a.global()?"true":a.is("STUDENT")?"t.block_id=:block":grant("CLOAKROOM","t.id");order="b.name,t.name,t.id";search=List.of("t.name","b.name","t.item_type"); }
            case "cloakroomRequests" -> { from="cloakroom_requests t JOIN storage_rooms s ON s.id=t.storage_id LEFT JOIN cloakroom c ON c.id=t.entry_id";select+=",s.name AS storage_name,c.token_number,c.status AS entry_status";where=a.is("STUDENT")?"t.student_id=:uid AND t.state<>'CANCELLED'":"false";order="t.created_at DESC,t.id";search=List.of("s.name","t.item","t.state"); }
            case "maintenance" -> { from="maintenance t JOIN blocks b ON b.id=t.block_id LEFT JOIN users u ON u.id=t.student_id LEFT JOIN users h ON h.id=t.assignee_id";select+=",b.name AS block_name,u.name AS student_name,h.name AS assignee_name";where=a.global()?"true":a.is("STUDENT")?"t.student_id=:uid":grant("MAINTENANCE","t.block_id")+(a.is("HOUSEKEEPING")?" AND t.assignee_id=:uid":"");order="t.created_at DESC,t.id";search=List.of("b.name","t.room_label","t.category","t.description","t.status","h.name"); }
            case "scopes" -> { from="duty_scopes t JOIN users u ON u.id=t.user_id LEFT JOIN blocks b ON b.id=t.target_id LEFT JOIN messes m ON m.id=t.target_id LEFT JOIN storage_rooms s ON s.id=t.target_id";select+=",u.name AS user_name,u.role,COALESCE(b.name,m.name,s.name) AS target_name";where=a.global()?"true":"t.user_id=:uid";order="u.name,t.book,t.id";search=List.of("u.name","t.book","b.name","m.name","s.name"); }
            case "audit" -> { from="audit t JOIN users u ON u.id=t.actor_id";select+=",u.name AS actor_name";where=a.global()?"true":"(t.actor_id=:uid OR (t.resource_type='cloakroom' AND EXISTS (SELECT 1 FROM cloakroom c WHERE c.id=t.resource_id AND "+(a.is("STUDENT")?"c.student_id=:uid":grant("CLOAKROOM","c.storage_id"))+")))";order="t.created_at DESC,t.id";search=List.of("u.name","t.action","t.detail","t.resource_type"); }
            case "announcements" -> { from="announcements t";select+=",(SELECT b.name FROM blocks b WHERE b.id=t.block_id) AS block_name";where=a.global()?"true":"((t.active=true OR "+grant("HOSTEL","t.block_id")+") AND (t.block_id IS NULL OR t.block_id IN (:blocks)) AND (t.audience='ALL' OR t.audience=:role OR "+grant("HOSTEL","t.block_id")+"))";order="t.created_at DESC,t.id";search=List.of("t.title","t.body","t.level"); }
            default -> throw error(404,"Unknown record collection");
        }
        return new Query(select,from,"("+where+")",order,search);
    }
    String search(Query q,String text,Map<String,Object> p) {
        if(text==null||text.isBlank()) return "";
        if(text.length()>100) throw error(400,"Search is limited to 100 characters");
        p.put("q","%"+text.strip().toLowerCase(Locale.ROOT).replace("!","!!").replace("%","!%").replace("_","!_")+"%");
        return " AND ("+q.search().stream().map(f->"LOWER(COALESCE("+f+",'')) LIKE :q ESCAPE '!'").collect(java.util.stream.Collectors.joining(" OR "))+")";
    }
    @Transactional(readOnly=true)
    public Map<String,Object> page(Actor a,String resource,int page,int size,String text) { return page(a,resource,page,size,text,""); }
    Map<String,Object> page(Actor a,String resource,int page,int size,String text,String extra) {
        if(page<0||page>1000000||size<1||size>100) throw error(400,"Invalid page (size must be 1 to 100)");
        Query q=query(a,resource);var p=params(a);String where=q.where()+extra+search(q,text,p);
        long total=sql.queryForObject("SELECT count(*) FROM "+q.from()+" WHERE "+where,p,Long.class);
        p.put("limit",size);p.put("offset",(long)page*size);
        var items=sql.query("SELECT "+q.select()+" FROM "+q.from()+" WHERE "+where+" ORDER BY "+q.order()+" LIMIT :limit OFFSET :offset",p,(rs,n)->Store.readRow(rs));
        enrich(a,resource,items);
        return Map.of("items",items,"total",total,"page",page,"size",size);
    }
    void enrich(Actor a,String resource,List<Map<String,Object>> items) {
        for(var r:items) switch(resource) {
            case "users" -> { if(str(r,"role").equals("HOUSEKEEPING")) r.put("maintenanceBlockIds",db.list("SELECT target_id FROM duty_scopes WHERE user_id=? AND book='MAINTENANCE' AND active=true",str(r,"id")).stream().map(g->str(g,"targetId")).toList()); }
            case "messes" -> r.put("blockIds",db.list("SELECT block_id FROM mess_blocks WHERE mess_id=?",str(r,"id")).stream().map(b->str(b,"blockId")).toList());
            case "outings" -> r.put("overdue",str(r,"status").equals("OUT")&&Instant.parse(str(r,"expectedReturnAt")).isBefore(Instant.now()));
            case "polls" -> {
                var p=params(a);p.put("poll",str(r,"id"));
                String visible=a.global()||a.is("STUDENT")||a.has("MESS",str(r,"messId"))?"true":grant("HOSTEL","v.block_id");
                r.put("options",sql.query("SELECT o.*,(SELECT count(*) FROM votes v WHERE v.option_id=o.id AND "+visible+") AS votes FROM poll_options o WHERE o.poll_id=:poll ORDER BY o.id",p,(rs,n)->Store.readRow(rs)));
                r.put("myVote",db.list("SELECT option_id FROM votes WHERE poll_id=? AND student_id=?",str(r,"id"),a.id()).stream().map(v->str(v,"optionId")).findFirst().orElse(""));
            }
        }
    }
    public long count(Actor a,String resource,String condition) {
        Query q=query(a,resource);return sql.queryForObject("SELECT count(*) FROM "+q.from()+" WHERE "+q.where()+" AND "+condition,params(a),Long.class);
    }
    public double rating(Actor a) {
        Query q=query(a,"feedback");return sql.queryForObject("SELECT COALESCE(AVG(t.rating),0) FROM "+q.from()+" WHERE "+q.where(),params(a),Double.class);
    }
    @Transactional(readOnly=true)
    public Object options(Actor a,String resource,String text,String block,String book,String selected) {
        String extra="";
        switch(resource) {
            case "students" -> { resource="users"; extra=" AND t.role='STUDENT' AND t.active=true"; if(!a.global()) { if(!List.of("OUTINGS","DISCIPLINE","HOSTEL").contains(book)) throw error(400,"Select a duty book");extra+=" AND "+grant(book,"t.block_id"); } }
            case "staff" -> { a.require("ADMIN");resource="users";extra=" AND t.role NOT IN ('ADMIN','DIRECTOR','STUDENT')"; }
            case "housekeeping" -> { resource="users";extra=" AND t.role='HOUSEKEEPING' AND t.active=true"; }
            case "rooms" -> extra=" AND t.active=true";
            case "blocks","messes","storageRooms" -> extra=" AND t.active=true";
            default -> throw error(400,"Unknown option collection");
        }
        // Target IDs are bound as parameters; lookup filters never widen access.
        Query q=query(a,resource);var p=params(a);p.put("selected",selected);p.put("filterBlock",block);
        if(!block.isBlank()) {
            if(resource.equals("rooms")||resource.equals("storageRooms")) extra+=" AND t.block_id=:filterBlock";
            else if(resource.equals("users") && extra.contains("HOUSEKEEPING")) extra+=" AND EXISTS(SELECT 1 FROM duty_scopes h WHERE h.user_id=t.id AND h.book='MAINTENANCE' AND h.active=true AND h.target_id=:filterBlock)";
            else if(resource.equals("messes")) extra+=" AND EXISTS(SELECT 1 FROM mess_blocks mb WHERE mb.mess_id=t.id AND mb.block_id=:filterBlock)";
        }
        String filter=selected.isBlank()?extra+search(q,text,p):" AND t.id=:selected";
        var items=sql.query("SELECT "+q.select()+" FROM "+q.from()+" WHERE "+q.where()+filter+" ORDER BY "+q.order()+" LIMIT 30",p,(rs,n)->Store.readRow(rs));
        return items.stream().map(r->Map.of("value",str(r,"id"),"blockId",str(r,"blockId"),"label",String.join(" · ",java.util.stream.Stream.of(str(r,"name"),str(r,"number"),str(r,"rollNo"),str(r,"blockName")).filter(s->!s.isBlank()).toList()))).toList();
    }
}
