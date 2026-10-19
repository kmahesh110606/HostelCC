package in.hostelcc;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
@RestController @RequestMapping("/api/campus")
public class CampusController {
    final CampusService service;
    public CampusController(CampusService service){this.service=service;}
    @GetMapping("/floors") Object floors(@AuthenticationPrincipal Actor a,@RequestParam String block){return service.floors(a,block);}
    @GetMapping("/floors/{id}") Object floor(@AuthenticationPrincipal Actor a,@PathVariable String id){return service.floor(a,id);}
    @PostMapping("/floors") Object create(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object>b){return Map.of("id",service.saveFloor(a,null,b));}
    @PutMapping("/floors/{id}") Object update(@AuthenticationPrincipal Actor a,@PathVariable String id,@RequestBody Map<String,Object>b){return Map.of("id",service.saveFloor(a,id,b));}
    @GetMapping("/rooms/{id}/students") Object room(@AuthenticationPrincipal Actor a,@PathVariable String id){return service.occupants(a,id);}
    @GetMapping("/students/{id}") Object student(@AuthenticationPrincipal Actor a,@PathVariable String id){return service.student(a,id);}
    @GetMapping("/students/{id}/{kind}") Object history(@AuthenticationPrincipal Actor a,@PathVariable String id,@PathVariable String kind,@RequestParam(defaultValue="0") int page){return service.history(a,id,kind,page);}
    @PostMapping("/gate") Object gate(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object>b){return Map.of("id",service.gate(a,b));}
    @GetMapping("/books") Object books(@AuthenticationPrincipal Actor a){return service.books(a);}
    @PostMapping("/books") Object createBook(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object>b){return Map.of("id",service.book(a,null,b));}
    @PutMapping("/books/{id}") Object updateBook(@AuthenticationPrincipal Actor a,@PathVariable String id,@RequestBody Map<String,Object>b){return Map.of("id",service.book(a,id,b));}
}
