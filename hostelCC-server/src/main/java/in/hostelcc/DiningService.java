package in.hostelcc;

import java.time.Instant;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

@Service
public class DiningService {
    final Store db; final DirectoryService directory; final MessService menus;
    public DiningService(Store db,DirectoryService directory,MessService menus) { this.db=db;this.directory=directory;this.menus=menus; }
    boolean enabled(String mess) { return bool(db.one("SELECT * FROM messes WHERE id=?",mess),"feedbackEnabled"); }
    public Object menu(Actor a,String mess) {directory.mess(a,mess);if(a.is("MESS_MANAGER"))throw error(403,"Caterers can read feedback only");return db.list("SELECT * FROM menus WHERE mess_id=? ORDER BY CASE weekday WHEN 'MON' THEN 1 WHEN 'TUE' THEN 2 WHEN 'WED' THEN 3 WHEN 'THU' THEN 4 WHEN 'FRI' THEN 5 WHEN 'SAT' THEN 6 ELSE 7 END",mess);}
    public Object feedback(Actor a,String mess,int page) {directory.mess(a,mess);if(a.is("STUDENT"))throw error(403,"Student responses are private");if(page<0||page>100000)throw error(400,"Invalid page");var items=db.list("SELECT f.*,s.title AS session_title FROM food_feedback f JOIN feedback_sessions s ON s.id=f.session_id WHERE s.mess_id=? ORDER BY f.id LIMIT 25 OFFSET ?",mess,page*25);for(var row:items)row.put("items",db.list("SELECT i.name,r.rating FROM item_ratings r JOIN food_items i ON i.id=r.item_id WHERE r.feedback_id=? ORDER BY i.name",str(row,"id")));return Map.of("items",items,"page",page,"size",25,"total",db.count("SELECT count(*) FROM food_feedback f JOIN feedback_sessions s ON s.id=f.session_id WHERE s.mess_id=?",mess));}
    @Transactional
    public void enable(Actor a,Map<String,Object> b) { String mess=required(b,"messId",64);directory.manageMess(a,mess);db.exec("UPDATE messes SET feedback_enabled=? WHERE id=?",bool(b,"enabled"),mess);db.audit(a,"FEEDBACK_SWITCH","messes",mess,null,"Enabled: "+bool(b,"enabled")); }
    public Object sessions(Actor a,String mess,int page) {
        directory.mess(a,mess);
        if(a.is("MESS_MANAGER")) throw error(403,"Caterers can read feedback only");
        if(page<0||page>100000)throw error(400,"Invalid page"); var rows=db.list("SELECT * FROM feedback_sessions WHERE mess_id=? ORDER BY opens_at DESC,id LIMIT 25 OFFSET ?",mess,page*25);
        for(var row:rows) { String id=str(row,"id");row.put("items",db.list("SELECT i.id,i.name FROM session_items s JOIN food_items i ON i.id=s.item_id WHERE s.session_id=? ORDER BY i.name",id));row.put("submitted",a.is("STUDENT") && db.count("SELECT count(*) FROM feedback_participation WHERE session_id=? AND student_id=?",id,a.id())>0); }
        return Map.of("enabled",enabled(mess),"sessions",rows,"total",db.count("SELECT count(*) FROM feedback_sessions WHERE mess_id=?",mess),"page",page,"size",25);
    }
    @Transactional
    public String session(Actor a,Map<String,Object> b) {
        String mess=required(b,"messId",64);directory.manageMess(a,mess);
        String title=required(b,"title",150),opens=instant(b,"opensAt"),closes=instant(b,"closesAt");
        if(!Instant.parse(closes).isAfter(Instant.parse(opens))) throw error(400,"Closing time must follow opening time");
        var names=DirectoryService.ids(b,"items");if(names.isEmpty()||names.size()>40) throw error(400,"Provide 1 to 40 food items");
        db.one("SELECT id FROM messes WHERE id=? AND active=true FOR UPDATE",mess);
        String id=id();db.exec("INSERT INTO feedback_sessions VALUES(?,?,?,?,?,?)",id,mess,title,opens,closes,bool(b,"enabled"));
        for(String name:names) { if(name.length()>140) throw error(400,"Food item names are limited to 140 characters");var old=db.list("SELECT id FROM food_items WHERE mess_id=? AND name=?",mess,name);String item=old.isEmpty()?id():str(old.getFirst(),"id");if(old.isEmpty())db.exec("INSERT INTO food_items(id,mess_id,name) VALUES(?,?,?)",item,mess,name);db.exec("INSERT INTO session_items VALUES(?,?)",id,item); }
        db.audit(a,"CREATE_FEEDBACK_SESSION","feedbackSessions",id,null,title);return id;
    }
    @Transactional
    public void state(Actor a,String id,Map<String,Object> b) { var s=db.one("SELECT * FROM feedback_sessions WHERE id=? FOR UPDATE",id);directory.manageMess(a,str(s,"messId"));db.exec("UPDATE feedback_sessions SET enabled=? WHERE id=?",bool(b,"enabled"),id);db.audit(a,"SET_FEEDBACK_SESSION","feedbackSessions",id,null,"Enabled: "+bool(b,"enabled")); }
    @Transactional
    public void submit(Actor a,String session,Map<String,Object> b) {
        a.require("STUDENT");
        var settings=db.one("SELECT * FROM messes WHERE id=? FOR UPDATE",a.messId());
        var s=db.one("SELECT * FROM feedback_sessions WHERE id=? FOR UPDATE",session);
        if(!str(s,"messId").equals(a.messId())) throw error(403,"This session is not for your caterer");
        Instant now=Instant.now();
        if(!bool(settings,"feedbackEnabled")||!bool(s,"enabled")||now.isBefore(Instant.parse(str(s,"opensAt")))||!now.isBefore(Instant.parse(str(s,"closesAt")))) throw error(409,"Feedback is closed");
        if(db.count("SELECT count(*) FROM feedback_participation WHERE session_id=? AND student_id=?",session,a.id())>0) throw error(409,"Feedback already submitted for this session");
        int rating=integer(b,"rating",1,5);String comment=optional(b,"comment",4000),kind=choice(b,"kind","COMMENT","COMPLAINT");
        if(!(b.get("ratings") instanceof Map<?,?> ratings)) throw error(400,"Rate the session food items");
        var items=db.list("SELECT item_id FROM session_items WHERE session_id=?",session);
        if(ratings.size()!=items.size()) throw error(400,"Rate every listed item exactly once");
        Map<String,Integer> checked=new LinkedHashMap<>();
        for(var item:items) { String id=str(item,"itemId");checked.put(id,integer(Map.of("rating",ratings.get(id)==null?0:ratings.get(id)),"rating",1,5)); }
        // Participation has no response ID or timestamp. Responses have no student, block or timestamp.
        db.exec("INSERT INTO feedback_participation VALUES(?,?)",session,a.id());
        String id=id();db.exec("INSERT INTO food_feedback VALUES(?,?,?,?,?)",id,session,rating,comment,kind);
        checked.forEach((item,value)->db.exec("INSERT INTO item_ratings VALUES(?,?,?)",id,item,value));
    }
    public Object performance(Actor a,String mess) {
        directory.manageMess(a,mess);
        var caterer=db.one("SELECT count(*) AS responses,COALESCE(AVG(CAST(f.rating AS decimal)),0) AS rating FROM food_feedback f JOIN feedback_sessions s ON s.id=f.session_id WHERE s.mess_id=?",mess);
        var items=db.list("SELECT i.id,i.name,count(r.rating) AS responses,COALESCE(AVG(CAST(r.rating AS decimal)),0) AS rating FROM food_items i LEFT JOIN item_ratings r ON r.item_id=i.id WHERE i.mess_id=? GROUP BY i.id,i.name ORDER BY i.name",mess);
        return Map.of("caterer",caterer,"items",items);
    }
    @Transactional
    public Object upload(Actor a,Map<String,Object> b) {
        String mess=required(b,"messId",64);directory.manageMess(a,mess);
        if(b.containsKey("csv")) {
            var table=StudentImport.parse(required(b,"csv",100000));
            if(table.size()<2||!table.getFirst().equals(List.of("day","breakfast","lunch","snacks","dinner")))throw error(400,"Use the menu CSV template headers");
            var converted=new ArrayList<Map<String,Object>>();
            for(int i=1;i<table.size();i++){var values=table.get(i);if(values.size()!=5)throw error(400,"Menu row "+(i+1)+" must contain five columns");var row=new HashMap<String,Object>();for(int col=0;col<5;col++)row.put(table.getFirst().get(col),values.get(col));converted.add(row);}
            b=new HashMap<>(b);b.put("menus",converted);
        }
        if(!(b.get("menus") instanceof List<?> entries)||entries.isEmpty()||entries.size()>7) throw error(400,"Upload 1 to 7 daily menus");
        Set<String> days=new HashSet<>();
        for(Object entry:entries) { if(!(entry instanceof Map<?,?> raw))throw error(400,"Invalid menu row");var row=new HashMap<String,Object>();raw.forEach((k,v)->row.put(k.toString(),v));row.put("messId",mess);if(!days.add(str(row,"day")))throw error(400,"Duplicate weekday");menus.menu(a,row); }
        return Map.of("imported",entries.size());
    }
}
