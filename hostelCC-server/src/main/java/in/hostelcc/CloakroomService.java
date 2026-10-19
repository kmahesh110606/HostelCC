package in.hostelcc;

import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

@Service
public class CloakroomService {
    final Store db; final DirectoryService directory; final ResidenceService residence;
    public CloakroomService(Store db,DirectoryService d,ResidenceService r) { this.db=db;directory=d;residence=r; }
    @Transactional
    public Map<String,Object> request(Actor a,Map<String,Object> b) {
        a.require("STUDENT","ADMIN"); String uid=a.is("STUDENT")?a.id():required(b,"studentId",64);
        db.one("SELECT id FROM users WHERE id=? FOR UPDATE",uid); var u=directory.student(uid);
        if(!bool(u,"cloakroomAccess")) throw error(403,"Cloakroom access has not been enabled for this student");
        String storage=required(b,"storageId",64); var room=db.one("SELECT * FROM storage_rooms WHERE id=? AND active=true AND block_id=?",storage,str(u,"blockId"));
        String item=str(room,"itemType");
        if(db.count("SELECT count(*) FROM cloakroom WHERE student_id=? AND item=? AND status='STORED'",uid,item)>0) throw error(409,"This item is already stored");
        var pending=db.list("SELECT * FROM cloakroom_requests WHERE student_id=? AND item=? AND state='PENDING' FOR UPDATE",uid,item);
        if(!pending.isEmpty()) {
            if(!str(pending.getFirst(),"storageId").equals(storage)) throw error(409,"Cancel the pending QR before choosing another room");
            return pending.getFirst();
        }
        String id=id(),qr="HCC1:"+UUID.randomUUID()+":"+UUID.randomUUID();
        db.exec("INSERT INTO cloakroom_requests(id,qr_token,student_id,storage_id,item,created_at) VALUES(?,?,?,?,?,?)",id,qr,uid,storage,item,now());
        return db.one("SELECT * FROM cloakroom_requests WHERE id=?",id);
    }
    @Transactional
    public void cancel(Actor a,String id) {
        a.require("STUDENT","ADMIN"); var row=db.one("SELECT * FROM cloakroom_requests WHERE id=? FOR UPDATE",id);
        if(!a.is("ADMIN")&&!a.id().equals(str(row,"studentId"))) throw error(403,"This QR belongs to another student");
        if(!str(row,"state").equals("PENDING")) throw error(409,"Only an unused QR can be cancelled");
        db.exec("UPDATE cloakroom_requests SET state='CANCELLED' WHERE id=?",id);
    }
    @Transactional
    public Map<String,Object> scan(Actor a,Map<String,Object> b) {
        String room=required(b,"storageId",64); a.duty("CLOAKROOM",room);
        var rows=db.list("SELECT * FROM cloakroom_requests WHERE qr_token=? FOR UPDATE",required(b,"qrToken",100));
        if(rows.isEmpty()) throw error(400,"This QR is not a HostelCC item pass"); var request=rows.getFirst();
        String mode=choice(b,"mode","submit","return"),state=str(request,"state");
        if(state.equals("CANCELLED")) throw error(409,"This item pass was cancelled");
        if(mode.equals("submit")) {
            if(!room.equals(str(request,"storageId"))) throw error(403,"This item pass is for a different cloakroom");
            if(state.equals("PROCESSED")) return db.one("SELECT c.*,u.name AS student_name,u.roll_no FROM cloakroom c JOIN users u ON u.id=c.student_id WHERE c.id=?",str(request,"entryId"));
            var input=new HashMap<String,Object>(); input.put("studentId",str(request,"studentId")); input.put("storageId",room); input.put("item",str(request,"item"));
            input.put("itemCondition",choice(b,"itemCondition","GOOD","DAMAGED")); input.put("notes",optional(b,"notes",4000));
            String entry=residence.cloakroom(a,input);
            db.exec("UPDATE cloakroom_requests SET state='PROCESSED',entry_id=? WHERE id=?",entry,str(request,"id"));
            return db.one("SELECT c.*,u.name AS student_name,u.roll_no FROM cloakroom c JOIN users u ON u.id=c.student_id WHERE c.id=?",entry);
        }
        if(!state.equals("PROCESSED")) throw error(409,"This item has not been checked in");
        var entry=db.one("SELECT * FROM cloakroom WHERE id=? FOR UPDATE",str(request,"entryId"));
        if(!room.equals(str(entry,"storageId"))) throw error(403,"This item is held in a different cloakroom");
        if(str(entry,"status").equals("RETURNED")) return entry;
        residence.cloakroomAction(a,str(entry,"id"),Map.of("action","return","receipt",str(entry,"receipt"),"note",required(b,"notes",2000)));
        return db.one("SELECT * FROM cloakroom WHERE id=?",str(entry,"id"));
    }
}
