package in.hostelcc;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
@RestController @RequestMapping("/api/dining")
public class DiningController {
    final DiningService service;
    public DiningController(DiningService service){this.service=service;}
    @GetMapping("/menus") Object menus(@AuthenticationPrincipal Actor a,@RequestParam String mess){return service.menu(a,mess);}
    @GetMapping("/feedback") Object feedback(@AuthenticationPrincipal Actor a,@RequestParam String mess,@RequestParam(defaultValue="0") int page){return service.feedback(a,mess,page);}
    @PostMapping("/enabled") Object enable(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object>b){service.enable(a,b);return Map.of("message","Updated");}
    @GetMapping("/sessions") Object sessions(@AuthenticationPrincipal Actor a,@RequestParam String mess,@RequestParam(defaultValue="0") int page){return service.sessions(a,mess,page);}
    @PostMapping("/sessions") Object session(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object>b){return Map.of("id",service.session(a,b));}
    @PostMapping("/sessions/{id}/state") Object state(@AuthenticationPrincipal Actor a,@PathVariable String id,@RequestBody Map<String,Object>b){service.state(a,id,b);return Map.of("message","Updated");}
    @PostMapping("/sessions/{id}/submit") Object submit(@AuthenticationPrincipal Actor a,@PathVariable String id,@RequestBody Map<String,Object>b){service.submit(a,id,b);return Map.of("message","Feedback submitted");}
    @GetMapping("/performance") Object performance(@AuthenticationPrincipal Actor a,@RequestParam String mess){return service.performance(a,mess);}
    @PostMapping("/menus/upload") Object upload(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object>b){return service.upload(a,b);}
}
