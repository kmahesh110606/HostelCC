package in.hostelcc;

import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

@Service
public class CampusService {
    final Store db; final DirectoryService directory;
    public CampusService(Store db,DirectoryService directory){this.db=db;this.directory=directory;}
    void viewBlock(Actor a,String block) {
        if(a.global()) return;
        if(a.is("WARDEN","SUPERVISOR") && (a.has("HOSTEL",block)||a.has("OUTINGS",block)||a.has("DISCIPLINE",block)))return;
        throw error(403,"This block is outside your duties");
    }
    public Object floors(Actor a,String block) {viewBlock(a,block);return db.list("SELECT * FROM floors WHERE block_id=? ORDER BY sort_order,name",block);}
    public Object floor(Actor a,String id) {
        var f=db.one("SELECT * FROM floors WHERE id=?",id);viewBlock(a,str(f,"blockId"));
        f.put("elements",db.list("SELECT e.*,r.number AS room_number,r.capacity,(SELECT count(*) FROM users u WHERE u.room_id=e.room_id AND u.active=true) AS occupied FROM floor_elements e LEFT JOIN rooms r ON r.id=e.room_id WHERE e.floor_id=? ORDER BY e.id",id));return f;
    }
    @Transactional
    public String saveFloor(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN");String block=required(b,"blockId",64),name=required(b,"name",80);int width=integer(b,"width",100,3000),height=integer(b,"height",100,3000),order=integer(b,"sortOrder",-20,200);
        db.one("SELECT id FROM blocks WHERE id=?",block);
        if(!(b.get("elements") instanceof List<?> elements)||elements.size()>300)throw error(400,"A floor supports up to 300 elements");
        if(id==null){id=id();db.exec("INSERT INTO floors(id,block_id,name,sort_order,width,height) VALUES(?,?,?,?,?,?)",id,block,name,order,width,height);}
        else {var old=db.one("SELECT * FROM floors WHERE id=? FOR UPDATE",id);if(!block.equals(str(old,"blockId")))throw error(400,"A floor cannot move blocks");if(integer(b,"version",0,Integer.MAX_VALUE)!=((Number)old.get("version")).intValue())throw error(409,"This layout changed. Reload before editing.");db.exec("UPDATE floors SET name=?,sort_order=?,width=?,height=?,version=version+1 WHERE id=?",name,order,width,height,id);db.exec("DELETE FROM floor_elements WHERE floor_id=?",id);}
        Set<String> used=new HashSet<>();
        for(Object entry:elements) {
            if(!(entry instanceof Map<?,?> raw))throw error(400,"Invalid layout element");var e=new HashMap<String,Object>();raw.forEach((k,v)->e.put(k.toString(),v));
            String kind=choice(e,"kind","ROOM","CORRIDOR","STAIRS","LIFT","WALL","LABEL"),room=optional(e,"roomId",64),label=optional(e,"label",100);
            int x=integer(e,"x",0,width),y=integer(e,"y",0,height),w=integer(e,"width",5,width),h=integer(e,"height",5,height);
            if(x+w>width||y+h>height)throw error(400,"Element extends outside the floor");
            if(kind.equals("ROOM")){if(room.isBlank()||!used.add(room))throw error(400,"Select a different room for each room shape");db.one("SELECT id FROM rooms WHERE id=? AND block_id=?",room,block);}else room="";
            db.exec("INSERT INTO floor_elements VALUES(?,?,?,?,?,?,?,?,?)",id(),id,DirectoryService.nullable(room),kind,label,x,y,w,h);
        }
        db.audit(a,"SAVE_FLOOR","floors",id,block,name);return id;
    }
    public Object occupants(Actor a,String room) {var r=db.one("SELECT * FROM rooms WHERE id=?",room);viewBlock(a,str(r,"blockId"));return db.list("SELECT id,name,roll_no,email,phone FROM users WHERE room_id=? AND role='STUDENT' AND active=true ORDER BY name",room);}
    Map<String,Object> person(Actor a,String id) {var u=db.one("SELECT u.id,u.name,u.email,u.phone,u.roll_no,u.block_id,u.room_id,b.name AS block_name,r.number AS room_number,m.name AS mess_name FROM users u LEFT JOIN blocks b ON b.id=u.block_id LEFT JOIN rooms r ON r.id=u.room_id LEFT JOIN messes m ON m.id=u.mess_id WHERE u.id=? AND u.role='STUDENT'",id);if(!a.is("STUDENT")||!a.id().equals(id))viewBlock(a,str(u,"blockId"));return u;}
    public Object student(Actor a,String id){return person(a,id);}
    public Object history(Actor a,String id,String kind,int page) {
        person(a,id);if(page<0||page>100000)throw error(400,"Invalid page");
        String table=switch(kind){case "outings","discipline"->kind;case "gate"->"gate_events";case "cloakroom"->"cloakroom";default->throw error(400,"Unknown history");};
        String time=table.equals("gate_events")?"recorded_at":table.equals("cloakroom")?"submitted_at":"created_at";
        return Map.of("items",db.list("SELECT * FROM "+table+" WHERE student_id=? ORDER BY "+time+" DESC,id LIMIT 25 OFFSET ?",id,page*25),"total",db.count("SELECT count(*) FROM "+table+" WHERE student_id=?",id),"page",page,"size",25);
    }
    @Transactional
    public String gate(Actor a,Map<String,Object> b) {
        String student=required(b,"studentId",64);var u=directory.student(student);a.duty("OUTINGS",str(u,"blockId"));db.one("SELECT id FROM users WHERE id=? FOR UPDATE",student);
        String direction=choice(b,"direction","ENTRY","EXIT"),note=optional(b,"note",1000);
        var previous=db.list("SELECT direction FROM gate_events WHERE student_id=? ORDER BY recorded_at DESC,id DESC LIMIT 1",student);
        if(!previous.isEmpty()&&direction.equals(str(previous.getFirst(),"direction")))throw error(409,"The last gate event already records this direction");
        String id=id();db.exec("INSERT INTO gate_events VALUES(?,?,?,?,?,?,?)",id,student,str(u,"blockId"),direction,note,a.id(),now());db.audit(a,"GATE_"+direction,"gate",id,str(u,"blockId"),student);return id;
    }
    public Object books(Actor a) {a.require("ADMIN");return db.list("SELECT * FROM duty_books ORDER BY name");}
    @Transactional
    public String book(Actor a,String id,Map<String,Object>b) {a.require("ADMIN");String name=required(b,"name",100),base=choice(b,"baseBook","HOSTEL","OUTINGS","DISCIPLINE","MESS","MAINTENANCE","CLOAKROOM");if(id==null){id=id();db.exec("INSERT INTO duty_books VALUES(?,?,?,?)",id,name,base,true);}else{var old=db.one("SELECT * FROM duty_books WHERE id=? FOR UPDATE",id);if(!base.equals(str(old,"baseBook")))throw error(400,"Create a new book to change its permissions");db.exec("UPDATE duty_books SET name=?,active=? WHERE id=?",name,bool(b,"active"),id);if(!bool(b,"active"))db.exec("UPDATE duty_scopes SET active=false WHERE book_id=?",id);}db.audit(a,"SAVE_DUTY_BOOK","dutyBooks",id,null,name);return id;}
}
