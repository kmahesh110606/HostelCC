import { Download } from 'lucide-react';

export default function DownloadFooter() {
  return <footer className="download-footer">
    <span>HostelCC</span>
    <a className="button secondary" href="/downloads/HostelCC.apk" download="HostelCC.apk"><Download size={16} />Download Android APK</a>
    <button className="button secondary" disabled title="iOS release is not yet available">iOS App Store — Coming soon</button>
  </footer>;
}
