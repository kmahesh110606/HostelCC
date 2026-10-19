import { label, has } from './api';
export const roles = ['ADMIN', 'DIRECTOR', 'WARDEN', 'SUPERVISOR', 'STUDENT', 'MESS_MANAGER', 'HOUSEKEEPING'];
export const books = ['HOSTEL', 'MESS', 'OUTINGS', 'DISCIPLINE', 'MAINTENANCE', 'CLOAKROOM'];
const select = (name, title, options, extra = {}) => ({ name, title, type: 'select', options, ...extra });
const text = (name, title, extra = {}) => ({ name, title, ...extra });
const choices = values => values.map(value => ({ value, label: label(value) }));
export function fieldsFor(resource, data, user, values = {}, editing = false) {
  const opts = (key, filter = () => true) => (data[key] || []).filter(filter).map(r => ({ value: r.id, label: [r.name || r.number || r.studentName, r.blockName, r.rollNo].filter(Boolean).join(' · ') }));
  const blocks = opts('blocks', b => b.active && (user.role === 'ADMIN' || has(user, resource === 'outings' ? 'OUTINGS' : resource === 'discipline' ? 'DISCIPLINE' : resource === 'maintenance' ? 'MAINTENANCE' : 'HOSTEL', b.id)));
  const students = opts('users', u => u.role === 'STUDENT' && u.active && (user.role === 'ADMIN' || has(user, resource === 'discipline' ? 'DISCIPLINE' : 'OUTINGS', u.blockId)));
  const messes = opts('messes', m => m.active && (user.role === 'STUDENT' || has(user, 'MESS', m.id)));
  const state = editing ? [{ name: 'active', title: 'Active', type: 'checkbox' }] : [];
  switch (resource) {
    case 'blocks': return [text('name', 'Block name'), text('contactEmail', 'Contact email', { type: 'email', optional: true }), text('contactPhone', 'Contact phone', { optional: true }), ...state];
    case 'rooms': return [select('blockId', 'Block', blocks), text('number', 'Room number'), text('capacity', 'Beds', { type: 'number', min: 1, max: 20 }), select('roomType', 'Room type', choices(['AC', 'NON_AC'])), ...state];
    case 'messes': return [text('name', 'Mess / caterer name'), { name: 'blockIds', title: 'Blocks served', type: 'multi', remote: '/options/blocks', options: opts('blocks', b => b.active) }, ...state];
    case 'users': return [text('name', 'Full name'), text('email', 'Email address', { type: 'email' }), select('role', 'Role', choices(roles)), text('phone', 'Phone', { optional: true }), ...(values.role === 'STUDENT' ? [text('rollNo', 'Roll number'), select('blockId', 'Hostel block', opts('blocks', b => b.active)), select('roomId', 'Room', opts('rooms', r => r.active && r.blockId === values.blockId), { optional: true }), select('messId', 'Mess', opts('messes', m => m.active && m.blockIds.includes(values.blockId)), { optional: true }), { name: 'cloakroomAccess', title: 'Enable cloakroom item passes', type: 'checkbox' }] : values.role === 'MESS_MANAGER' ? [select('messId', 'Primary mess', opts('messes', m => m.active))] : []), ...state];
    case 'scopes': return [{name:'bookId',title:'Custom book (optional)',type:'select',optional:true,remote:'/options/books'}, select('userId', 'Staff member', opts('users', u => u.active && !['ADMIN', 'DIRECTOR', 'STUDENT'].includes(u.role))), select('book', 'Duty book', choices(books)), select('targetId', 'Assigned location', opts(values.book === 'MESS' ? 'messes' : values.book === 'CLOAKROOM' ? 'storageRooms' : 'blocks', r => r.active)), { name: 'active', title: 'Assignment enabled', type: 'checkbox' }];
    case 'announcements': return [text('title', 'Title'), text('body', 'Announcement', { type: 'textarea' }), select('level', 'Priority', choices(['INFO', 'WARNING', 'URGENT'])), select('audience', 'Audience', choices(['ALL', ...roles])), select('blockId', 'Block', blocks, { optional: user.role === 'ADMIN', placeholder: 'Campus-wide' }), ...state];
    case 'menus': return [select('messId', 'Mess', messes), select('day', 'Day', choices(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])), ...['breakfast', 'lunch', 'snacks', 'dinner'].map(meal => text(meal, label(meal), { type: 'textarea' }))];
    case 'polls': return [select('messId', 'Mess', messes), text('title', 'Question'), text('closesAt', 'Closes at', { type: 'datetime-local' }), text('options', 'Options, one per line', { type: 'textarea', lines: true })];
    case 'outings': return [...(user.role !== 'STUDENT' ? [select('studentId', 'Student', students)] : []), select('kind', 'Request type', choices(['OUTING', 'LEAVE', 'NIGHT_MESS'])), text('destination', 'Destination'), text('reason', 'Reason', { type: 'textarea' }), text('departureAt', 'Departure', { type: 'datetime-local' }), text('expectedReturnAt', 'Expected return', { type: 'datetime-local' })];
    case 'discipline': return [select('studentId', 'Student', students), text('violation', 'Violation'), text('actionTaken', 'Action taken'), text('notes', 'Details', { type: 'textarea', optional: true }), { name: 'cardHeld', title: 'ID card held', type: 'checkbox' }];
    case 'storage-rooms': return [text('name', 'Cloakroom name'), select('blockId', 'Block', opts('blocks', b => b.active)), select('itemType', 'Item type', choices(['CHAIR', 'BUCKET', 'CARTON', 'SUITCASE', 'MATTRESS', 'OTHER'])), text('capacity', 'Storage capacity', { type: 'number', min: 1 }), text('tokenStart', 'First token number', { type: 'number', min: 1 }), text('tokenEnd', 'Last token number', { type: 'number', min: 1 }), ...state];
    case 'cloakroom/request': return [...(user.role === 'ADMIN' ? [select('studentId', 'Student', opts('users', u => u.role === 'STUDENT' && u.active))] : []), select('storageId', 'Room and item type', (data.storageRooms || []).filter(r => r.active && (user.role !== 'ADMIN' || r.blockId === data.users.find(u => u.id === values.studentId)?.blockId)).map(r => ({ value: r.id, label: `${r.blockName} · ${r.name} · ${label(r.itemType)}` })))];
    case 'maintenance': return [...(user.role !== 'STUDENT' ? [select('blockId', 'Block', blocks), text('roomLabel', 'Room / location', { optional: true })] : []), select('category', 'Category', choices(['CLEANING', 'PLUMBING', 'ELECTRICAL', 'CARPENTRY', 'WATER', 'AC', 'OTHER'])), text('description', 'What needs attention?', { type: 'textarea' })];
    default: return [];
  }
}
export function defaults(resource, user) {
  return { active: true, role: 'STUDENT', audience: 'ALL', level: 'INFO', roomType: 'NON_AC', kind: 'OUTING', itemType: 'CHAIR', itemCondition: 'GOOD', book: 'HOSTEL', capacity: 2, tokenStart: 1, tokenEnd: 1000, day: 'MON', meal: 'LUNCH', rating: 5, mealDate: new Date().toLocaleDateString('en-CA'), messId: user.messId || '', blockIds: [] };
}

export function withLookups(fields, resource, values, data) {
  return fields.map(f => {
    let remote;
    const block = values.blockId || values.studentBlockId || data.users?.find(u => u.id === values.studentId)?.blockId || '';
    if (f.name === 'studentId') remote = `/options/students?book=${resource === 'discipline' ? 'DISCIPLINE' : 'OUTINGS'}`;
    if (f.name === 'userId') remote = '/options/staff';
    if (f.name === 'roomId') remote = `/options/rooms?block=${encodeURIComponent(block)}`;
    if (f.name === 'blockId') remote = '/options/blocks';
    if (f.name === 'messId') remote = `/options/messes?block=${encodeURIComponent(resource === 'users' ? block : '')}`;
    if (f.name === 'targetId') remote = `/options/${values.book === 'MESS' ? 'messes' : values.book === 'CLOAKROOM' ? 'storageRooms' : 'blocks'}`;
    if (f.name === 'storageId' && resource === 'cloakroom/request') remote = `/options/storageRooms?block=${encodeURIComponent(block)}`;
    return remote ? { ...f, remote } : f;
  });
}
