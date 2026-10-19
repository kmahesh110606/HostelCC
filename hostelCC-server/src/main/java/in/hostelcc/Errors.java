package in.hostelcc;

import java.util.Map;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.bind.MethodArgumentNotValidException;

@RestControllerAdvice
public class Errors {
    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<?> status(ResponseStatusException e) { return ResponseEntity.status(e.getStatusCode()).body(Map.of("message",e.getReason()==null?"Request failed":e.getReason())); }
    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<?> conflict() { return ResponseEntity.status(409).body(Map.of("message","A conflicting record already exists, or a referenced record is unavailable")); }
    @ExceptionHandler({MethodArgumentNotValidException.class,org.springframework.http.converter.HttpMessageNotReadableException.class})
    ResponseEntity<?> invalid() { return ResponseEntity.badRequest().body(Map.of("message","Check the supplied fields")); }
}
