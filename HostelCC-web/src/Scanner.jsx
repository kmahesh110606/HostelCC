import { useEffect, useRef, useState } from 'react';
import { Camera } from 'lucide-react';
export default function Scanner({ onRead }) {
  const video = useRef(), callback = useRef(onRead), [enabled, setEnabled] = useState(false), [error, setError] = useState('');
  callback.current = onRead;
  useEffect(() => {
    if (!enabled) return;
    let controls, disposed = false, accepted = false;
    import('@zxing/browser').then(({ BrowserQRCodeReader }) => new BrowserQRCodeReader().decodeFromVideoDevice(undefined, video.current, (result, _error, control) => {
      if (result && !accepted) { accepted = true; callback.current(result.getText()); control.stop(); setEnabled(false) }
    })).then(c => { controls = c; if (disposed) c.stop() }).catch(() => { setError('Camera access is unavailable. Allow camera access on HTTPS, or paste the item-pass code.'); setEnabled(false) });
    return () => { disposed = true; controls?.stop() };
  }, [enabled]);
  return <div className="scanner">{enabled && <video ref={video} autoPlay playsInline muted />}<button type="button" className="button secondary" onClick={() => { setError(''); setEnabled(!enabled) }}><Camera size={17} />{enabled ? 'Stop camera' : 'Scan with camera'}</button>{error && <p className="error">{error}</p>}</div>;
}
