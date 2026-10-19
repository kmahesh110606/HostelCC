package in.hostelcc;

import java.util.Map;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import static in.hostelcc.Store.*;

@RestController
@RequestMapping("/api")
public class ApiController {
    final DirectoryService directory; final ResidenceService residence; final MessService mess; final WorkspaceService workspace; final CloakroomService cloak; final RecordService records;
    public ApiController(DirectoryService d,ResidenceService r,MessService m,WorkspaceService w,CloakroomService c,RecordService records) { directory=d;residence=r;mess=m;workspace=w;cloak=c;this.records=records; }
    @PostMapping("/cloakroom/request") Object requestQr(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object> b) { return cloak.request(a,b); }
    @PostMapping("/cloakroom/scan") Object scan(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object> b) { return cloak.scan(a,b); }
    @PostMapping("/cloakroom/requests/{id}/cancel") Object cancelQr(@AuthenticationPrincipal Actor a,@PathVariable String id) { cloak.cancel(a,id); return Map.of("message","Item pass cancelled"); }
    @PostMapping("/polls/{id}/state") Object pollState(@AuthenticationPrincipal Actor a,@PathVariable String id,@RequestBody Map<String,Object> b) { mess.pollState(a,id,b); return Map.of("message","Poll updated"); }
    @GetMapping("/workspace") Object workspace(@AuthenticationPrincipal Actor a) { return workspace.load(a); }
    @GetMapping(value="/admin/export",produces="application/json") org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody export(@AuthenticationPrincipal Actor a) { a.require("ADMIN");return output->workspace.export(a,output); }
    @GetMapping("/records/{resource}") Object page(@AuthenticationPrincipal Actor a,@PathVariable String resource,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="25") int size,@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="") String mess) { return records.page(a,resource,page,size,q,mess); }
    @GetMapping("/options/{resource}") Object options(@AuthenticationPrincipal Actor a,@PathVariable String resource,@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="") String block,@RequestParam(defaultValue="") String book,@RequestParam(defaultValue="") String selected) { return records.options(a,resource,q,block,book,selected); }
    @PostMapping("/{resource}") Object create(@AuthenticationPrincipal Actor a,@PathVariable String resource,@RequestBody Map<String,Object> b) {
        String id=switch(resource) {
            case "blocks" -> directory.block(a,null,b);
            case "rooms" -> directory.room(a,null,b);
            case "messes" -> directory.messSave(a,null,b);
            case "users" -> directory.user(a,null,b);
            case "scopes" -> directory.scope(a,null,b);
            case "storage-rooms" -> directory.storage(a,null,b);
            case "announcements" -> mess.announcement(a,null,b);
            case "menus" -> mess.menu(a,b);
            case "polls" -> mess.poll(a,b);
            case "outings" -> residence.outing(a,b);
            case "discipline" -> residence.discipline(a,b);
            case "maintenance" -> residence.maintenance(a,b);
            default -> throw error(404,"Unknown resource");
        }; return Map.of("id",id,"message","Saved successfully");
    }
    @PutMapping("/{resource}/{id}") Object update(@AuthenticationPrincipal Actor a,@PathVariable String resource,@PathVariable String id,@RequestBody Map<String,Object> b) {
        switch(resource) {
            case "blocks" -> directory.block(a,id,b);
            case "rooms" -> directory.room(a,id,b);
            case "messes" -> directory.messSave(a,id,b);
            case "users" -> directory.user(a,id,b);
            case "scopes" -> directory.scope(a,id,b);
            case "storage-rooms" -> directory.storage(a,id,b);
            case "announcements" -> mess.announcement(a,id,b);
            default -> throw error(404,"Unknown resource");
        } return Map.of("message","Updated successfully");
    }
    @PostMapping("/{resource}/{id}/action") Object action(@AuthenticationPrincipal Actor a,@PathVariable String resource,@PathVariable String id,@RequestBody Map<String,Object> b) {
        switch(resource) {
            case "outings" -> residence.outingAction(a,id,b);
            case "discipline" -> residence.returnCard(a,id,b);
            case "cloakroom" -> residence.cloakroomAction(a,id,b);
            case "maintenance" -> residence.maintenanceAction(a,id,b);
            case "polls" -> mess.vote(a,id,b);
            default -> throw error(404,"Unknown resource");
        } return Map.of("message","Updated successfully");
    }
}
