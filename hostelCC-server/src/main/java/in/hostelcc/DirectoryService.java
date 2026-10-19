package in.hostelcc;

import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

@Service
public class DirectoryService {
    final Store db;
    static final String[] ROLES={"ADMIN","DIRECTOR","WARDEN","SUPERVISOR","STUDENT","MESS_MANAGER","HOUSEKEEPING"};
    public DirectoryService(Store db) { this.db=db; }
    public Map<String,Object> student(String id) {
        var u=db.one("SELECT * FROM users WHERE id=? AND role='STUDENT'",id);
        if(!bool(u,"active") || str(u,"blockId").isBlank()) throw error(409,"Student must be active and assigned to a block"); return u;
    }
    public void manageStudent(Actor a,Map<String,Object> student) {
        a.duty("HOSTEL",str(student,"blockId"));
    }
    public void mess(Actor a,String id) {
        if(a.global()) return;
        if(a.is("STUDENT","MESS_MANAGER") && id.equals(a.messId())) return;
        if(a.has("MESS",id)) return;
        if(db.list("SELECT block_id FROM mess_blocks WHERE mess_id=?",id).stream().anyMatch(b->a.has("HOSTEL",str(b,"blockId")))) return;
        throw error(403,"This mess is outside your assignment");
    }
    public boolean seesMess(Actor a,String id) { try { mess(a,id); return true; } catch(org.springframework.web.server.ResponseStatusException e) { return false; } }
    public void manageMess(Actor a,String id) { if(a.is("ADMIN","DIRECTOR")) return; a.require("WARDEN"); a.duty("MESS",id); }
    @Transactional
    public String block(Actor a,String id,Map<String,Object> body) {
        a.require("ADMIN"); String name=required(body,"name",100), email=optional(body,"contactEmail",254),phone=optional(body,"contactPhone",30);
        if(id==null) { id=id(); db.exec("INSERT INTO blocks(id,name,contact_email,contact_phone) VALUES(?,?,?,?)",id,name,email,phone); }
        else {
            db.one("SELECT id FROM blocks WHERE id=? FOR UPDATE",id);
            if(Boolean.FALSE.equals(body.get("active")) && (db.count("SELECT count(*) FROM users WHERE block_id=? AND active=true",id)>0 || db.count("SELECT count(*) FROM rooms WHERE block_id=? AND active=true",id)>0 || db.count("SELECT count(*) FROM storage_rooms WHERE block_id=? AND active=true",id)>0)) throw error(409,"Reassign students and deactivate rooms before closing this block");
            db.exec("UPDATE blocks SET name=?,contact_email=?,contact_phone=?,active=? WHERE id=?",name,email,phone,body.getOrDefault("active",true),id);
        }
        db.audit(a,"SAVE_BLOCK","blocks",id,id,name); return id;
    }
    @Transactional
    public String room(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN"); String block=required(b,"blockId",64),number=required(b,"number",20),type=choice(b,"roomType","AC","NON_AC"); int capacity=integer(b,"capacity",1,20);
        db.one("SELECT id FROM blocks WHERE id=? AND active=true",block);
        if(id==null) { id=id(); db.exec("INSERT INTO rooms(id,block_id,number,capacity,room_type) VALUES(?,?,?,?,?)",id,block,number,capacity,type); }
        else {
            var old=db.one("SELECT * FROM rooms WHERE id=? FOR UPDATE",id);
            if(!str(old,"blockId").equals(block)) throw error(409,"A room cannot be moved between blocks");
            long occupied=db.count("SELECT count(*) FROM users WHERE room_id=? AND active=true",id);
            if(occupied>capacity || occupied>0 && Boolean.FALSE.equals(b.get("active"))) throw error(409,"Reassign occupants before reducing capacity or deactivating this room");
            db.exec("UPDATE rooms SET number=?,capacity=?,room_type=?,active=? WHERE id=?",number,capacity,type,b.getOrDefault("active",true),id);
        }
        db.audit(a,"SAVE_ROOM","rooms",id,block,number); return id;
    }
    @Transactional
    public String messSave(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN"); String name=required(b,"name",120); var blocks=ids(b,"blockIds");
        if(blocks.isEmpty()) throw error(400,"Assign at least one block");
        for(String bid:blocks) db.one("SELECT id FROM blocks WHERE id=? AND active=true",bid);
        if(id==null) { id=id(); db.exec("INSERT INTO messes(id,name) VALUES(?,?)",id,name); }
        else {
            db.one("SELECT id FROM messes WHERE id=? FOR UPDATE",id);
            long occupied=db.count("SELECT count(*) FROM users WHERE mess_id=? AND role='STUDENT' AND active=true",id);
            if(occupied>0 && Boolean.FALSE.equals(b.get("active"))) throw error(409,"Reassign students before reducing capacity or deactivating this mess");
            for(var u:db.list("SELECT DISTINCT block_id FROM users WHERE mess_id=? AND role='STUDENT' AND active=true",id)) if(!blocks.contains(str(u,"blockId"))) throw error(409,"This mess still serves students in a removed block");
            db.exec("UPDATE messes SET name=?,active=? WHERE id=?",name,b.getOrDefault("active",true),id);
        }
        db.exec("DELETE FROM mess_blocks WHERE mess_id=?",id);
        for(String bid:blocks) db.exec("INSERT INTO mess_blocks VALUES(?,?)",id,bid);
        db.audit(a,"SAVE_MESS","messes",id,null,name); return id;
    }
    static List<String> ids(Map<String,Object> b,String key) {
        Object raw=b.getOrDefault(key,List.of()); if(!(raw instanceof List<?> list) || list.size()>100) throw error(400,"Invalid "+key);
        return list.stream().map(Object::toString).filter(s->!s.isBlank()).distinct().toList();
    }
    public void assignMess(String uid,String mess,String block) {
        var m=db.one("SELECT * FROM messes WHERE id=? AND active=true FOR UPDATE",mess);
        if(db.count("SELECT count(*) FROM mess_blocks WHERE mess_id=? AND block_id=?",mess,block)==0) throw error(400,"Mess does not serve this block");
    }
    @Transactional
    public String user(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN");
        db.one("SELECT id FROM otp_guard WHERE id=1 FOR UPDATE");
        String name=required(b,"name",150),email=required(b,"email",254).toLowerCase(Locale.ROOT),role=choice(b,"role",ROLES),phone=optional(b,"phone",30);
        if(!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) throw error(400,"Enter a valid email address");
        String block=optional(b,"blockId",64),room=optional(b,"roomId",64),mess=optional(b,"messId",64),roll=optional(b,"rollNo",40);
        boolean active=!Boolean.FALSE.equals(b.get("active"));
        var old=id==null?null:db.one("SELECT * FROM users WHERE id=? FOR UPDATE",id);
        if(old!=null && str(old,"role").equals("STUDENT") && !role.equals("STUDENT")) throw error(409,"Student identity is retained for historical records; deactivate it and create a staff account instead");
        if(old!=null && str(old,"role").equals("ADMIN") && (!role.equals("ADMIN")||!active) && db.count("SELECT count(*) FROM users WHERE role='ADMIN' AND active=true")<=1) throw error(409,"Keep at least one active administrator");
        if(id==null) id=id();
        if(role.equals("STUDENT")) {
            if(block.isEmpty() || roll.isEmpty()) throw error(400,"Students need a roll number and block");
            db.one("SELECT id FROM blocks WHERE id=? AND active=true",block);
            if(!room.isEmpty()) {
                var r=db.one("SELECT * FROM rooms WHERE id=? AND block_id=? AND active=true FOR UPDATE",room,block);
                if(active && db.count("SELECT count(*) FROM users WHERE room_id=? AND active=true AND id<>?",room,id)>=((Number)r.get("capacity")).intValue()) throw error(409,"Selected room is full");
            }
            if(active && !mess.isEmpty()) assignMess(id,mess,block);
        } else { block=""; room=""; roll=""; }
        if(role.equals("MESS_MANAGER") && mess.isEmpty()) throw error(400,"Assign a mess to the manager");
        if(!role.equals("STUDENT") && !role.equals("MESS_MANAGER")) mess="";
        if(!mess.isEmpty()) db.one("SELECT id FROM messes WHERE id=?",mess);
        if(old==null) db.exec("INSERT INTO users(id,email,name,role,phone,roll_no,block_id,room_id,mess_id,cloakroom_access,active,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",id,email,name,role,phone,nullable(roll),nullable(block),nullable(room),nullable(mess),bool(b,"cloakroomAccess"),active,now());
        else {
            db.exec("UPDATE users SET email=?,name=?,role=?,phone=?,roll_no=?,block_id=?,room_id=?,mess_id=?,cloakroom_access=?,active=? WHERE id=?",email,name,role,phone,nullable(roll),nullable(block),nullable(room),nullable(mess),bool(b,"cloakroomAccess"),active,id);
            db.exec("UPDATE sessions SET revoked=true WHERE user_id=?",id);
            db.exec("DELETE FROM otp_challenges WHERE user_id=?",id);
            if(!role.equals(str(old,"role"))) db.exec("UPDATE duty_scopes SET active=false WHERE user_id=?",id);
        }
        db.audit(a,old==null?"CREATE_USER":"UPDATE_USER","users",id,nullable(block),"Role: "+role+"; active: "+active); return id;
    }
    static String nullable(String s) { return s==null||s.isBlank()?null:s; }
    @Transactional
    public String storage(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN"); String name=required(b,"name",120),block=required(b,"blockId",64); int capacity=integer(b,"capacity",1,100000);
        String item=choice(b,"itemType","CHAIR","BUCKET","CARTON","SUITCASE","MATTRESS","OTHER");
        int start=integer(b,"tokenStart",1,100000000),end=integer(b,"tokenEnd",start,100000000);
        db.one("SELECT id FROM blocks WHERE id=? AND active=true",block);
        if(id==null) { id=id(); db.exec("INSERT INTO storage_rooms(id,block_id,name,capacity,item_type,token_start,token_end,next_token) VALUES(?,?,?,?,?,?,?,?)",id,block,name,capacity,item,start,end,start); }
        else {
            var old=db.one("SELECT * FROM storage_rooms WHERE id=? FOR UPDATE",id);
            if(!str(old,"blockId").equals(block)) throw error(409,"A storage room cannot change blocks");
            if(!str(old,"itemType").equals(item) || ((Number)old.get("tokenStart")).intValue()!=start) throw error(409,"Item type and starting token are fixed; create another storage room for a new range");
            if(end<((Number)old.get("nextToken")).intValue()-1) throw error(409,"The range must retain every issued token");
            long used=db.count("SELECT count(*) FROM cloakroom WHERE storage_id=? AND status='STORED'",id);
            if(used>capacity || used>0 && Boolean.FALSE.equals(b.get("active"))) throw error(409,"Move or return stored items first");
            db.exec("UPDATE storage_rooms SET name=?,capacity=?,active=?,token_end=? WHERE id=?",name,capacity,b.getOrDefault("active",true),end,id);
        }
        db.audit(a,"SAVE_STORAGE_ROOM","storageRooms",id,block,name); return id;
    }
    @Transactional
    public String scope(Actor a,String assignmentId,Map<String,Object> b) {
        a.require("ADMIN"); b=new HashMap<>(b); if(!optional(b,"bookId",64).isBlank())b.put("book",str(db.one("SELECT * FROM duty_books WHERE id=? AND active=true",str(b,"bookId")),"baseBook")); String uid=required(b,"userId",64),book=choice(b,"book","HOSTEL","MESS","OUTINGS","DISCIPLINE","MAINTENANCE","CLOAKROOM"),target=required(b,"targetId",64);
        db.one("SELECT id FROM otp_guard WHERE id=1 FOR UPDATE");
        if(assignmentId!=null) db.one("SELECT id FROM duty_scopes WHERE id=? FOR UPDATE",assignmentId);
        boolean enabled=!Boolean.FALSE.equals(b.get("active"));
        var user=db.one("SELECT * FROM users WHERE id=?",uid); String role=str(user,"role");
        if(enabled && !bool(user,"active")) throw error(409,"Reactivate the staff account before enabling a duty");
        if(List.of("ADMIN","DIRECTOR","STUDENT").contains(role)) throw error(400,"Duty assignments are for operational staff");
        if(role.equals("HOUSEKEEPING") && !List.of("CLOAKROOM","MAINTENANCE").contains(book)) throw error(400,"Housekeeping scopes are cloakroom and maintenance");
        if(role.equals("MESS_MANAGER") && !book.equals("MESS")) throw error(400,"Mess managers can be assigned mess books");
        String template=optional(b,"bookId",64); if(!template.isBlank()) { var custom=db.one("SELECT * FROM duty_books WHERE id=? AND active=true",template); if(!book.equals(str(custom,"baseBook"))) throw error(400,"Book permissions do not match"); }
        String table=book.equals("MESS")?"messes":book.equals("CLOAKROOM")?"storage_rooms":"blocks";
        db.one("SELECT id FROM "+table+" WHERE id=?"+(enabled?" AND active=true":""),target);
        var old=db.list("SELECT id FROM duty_scopes WHERE user_id=? AND book=? AND target_id=?",uid,book,target);
        if(assignmentId!=null && !old.isEmpty() && !assignmentId.equals(str(old.getFirst(),"id"))) throw error(409,"That duty assignment already exists; edit the existing assignment instead");
        String id=assignmentId!=null?assignmentId:old.isEmpty()?id():str(old.getFirst(),"id");
        if(assignmentId!=null) db.exec("UPDATE duty_scopes SET user_id=?,book=?,target_id=?,active=? WHERE id=?",uid,book,target,b.getOrDefault("active",true),id);
        else if(old.isEmpty()) db.exec("INSERT INTO duty_scopes(id,user_id,book,target_id,active) VALUES(?,?,?,?,?)",id,uid,book,target,b.getOrDefault("active",true));
        else db.exec("UPDATE duty_scopes SET active=? WHERE id=?",b.getOrDefault("active",true),id);
        db.exec("UPDATE duty_scopes SET book_id=? WHERE id=?",nullable(template),id);
        db.audit(a,"ASSIGN_DUTY","scopes",id,table.equals("blocks")?target:null,book+"; staff "+uid+"; target "+target+"; active "+b.getOrDefault("active",true)); return id;
    }
}
