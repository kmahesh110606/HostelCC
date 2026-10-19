import { useEffect, useRef, useState } from 'react';
import { api } from './api';

export function CollectionControls({ meta = {}, onLoad }) {
  const [query, setQuery] = useState('');
  const timer = useRef();
  useEffect(() => () => clearTimeout(timer.current), []);
  const page = meta.page || 0, size = meta.size || 25, total = meta.total || 0;
  return <div className="panel table-tools mb-4"><label className="search"><input aria-label="Search records" placeholder="Search all records…" value={query} maxLength={100} onChange={e => { const q = e.target.value; setQuery(q); clearTimeout(timer.current); timer.current = setTimeout(() => onLoad(0, q), 300) }} /></label><span>{total} records · Page {page + 1} of {Math.max(1, Math.ceil(total / size))}</span><div className="flex gap-3"><button className="button secondary" aria-label="Previous page" disabled={page === 0} onClick={() => onLoad(page - 1, query)}>Previous</button><button className="button secondary" aria-label="Next page" disabled={(page + 1) * size >= total} onClick={() => onLoad(page + 1, query)}>Next</button></div></div>;
}

export function RemoteSelect({ field, value, onChange }) {
  const [query, setQuery] = useState(''), [options, setOptions] = useState(field.options || []), [error, setError] = useState('');
  const selected = useRef(null);
  useEffect(() => {
    let live = true;
    const timer = setTimeout(async () => {
      try {
        const separator = field.remote.includes('?') ? '&' : '?';
        const result = await api(`${field.remote}${separator}q=${encodeURIComponent(query)}`);
        if (value && !result.some(o => o.value === value) && selected.current?.value !== value) {
          const found = await api(`${field.remote}${separator}selected=${encodeURIComponent(value)}`);
          selected.current = found[0] || null;
        }
        if (live) { setOptions(selected.current && !result.some(o => o.value === selected.current.value) ? [selected.current, ...result] : result); setError('') }
      } catch (e) { if (live) setError(e.message) }
    }, query ? 250 : 0);
    return () => { live = false; clearTimeout(timer) };
  }, [field.remote, query, value]);
  return <span className="block"><input aria-label={`Search ${field.title.toLowerCase()}`} placeholder="Type to search…" value={query} onChange={e => setQuery(e.target.value)} maxLength={100} /><select aria-label={field.title} required={!field.optional} value={value || ''} onChange={e => { const option = options.find(o => o.value === e.target.value); selected.current = option; onChange(e.target.value, option) }}><option value="">{field.placeholder || 'Select an option'}</option>{options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}</select>{error && <small role="alert" className="error">{error}</small>}</span>;
}

export function StudentCsvImport({ onDone }) {
  const [csv, setCsv] = useState(''), [report, setReport] = useState(null), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  async function send(commit) {
    setBusy(true); setError('');
    try { const result = await api(`/admin/students/import${commit ? '' : '/validate'}`, 'POST', { csv }); setReport(result); if (commit) await onDone(result.imported) }
    catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  return <div className="space-y-4"><p>Add blocks, rooms and messes first. Import up to 1,000 students per file. Existing accounts are never overwritten.</p><a className="action" href="/students-template.csv" download>Download CSV template</a><label className="block">Student CSV<input type="file" accept=".csv,text/csv" aria-label="Student CSV" disabled={busy} onChange={async e => { setReport(null); setError(''); const file = e.target.files[0]; if (!file) return; if (file.size > 500000) { setCsv(''); setError('Use a file smaller than 500 KB.'); return } setCsv(await file.text()) }} /></label>{csv && <button className="button secondary" disabled={busy} onClick={() => send(false)}>Validate file</button>}{report && <div><p>{report.count} valid students · {report.errors.length} errors</p>{report.errors.map(e => <p className="error" key={e.row}>Row {e.row}: {e.message}</p>)}{report.valid && <><ul>{report.preview.map(s => <li key={s.email}>{s.name} · {s.rollNo} · {s.email}</li>)}</ul><p className="muted">Preview shows the first 20 students.</p><button className="button primary" disabled={busy} onClick={() => send(true)}>Import {report.count} students</button></>}</div>}{error && <p role="alert" className="error">{error}</p>}</div>;
}
