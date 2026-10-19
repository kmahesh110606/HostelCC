import { test, expect } from '@playwright/test';

test('admin setup, scoped duties, student outings, item QR check-in and histories', async ({ browser, request }) => {
  async function code(email) {
    for (let i = 0; i < 20; i++) {
      {
        const box=await (await request.get(`${process.env.MAILPIT_URL || 'http://localhost:8025'}/api/v1/messages`)).json();
        const mail=box.messages.find(m=>m.To.some(to=>to.Address===email));
        if(mail){const message=await (await request.get(`${process.env.MAILPIT_URL || 'http://localhost:8025'}/api/v1/message/${mail.ID}`)).json();return message.Text.match(/\b\d{6}\b/)[0];}
        await new Promise(r=>setTimeout(r,100));continue;
      }

    }
    throw new Error('No local test OTP captured');
  }
  async function signIn(email, mobile = false) {
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1050 } });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto('/'); await page.getByLabel('Email address').fill(email); await page.getByRole('button', { name: 'Send sign-in code' }).click();
    await expect(page.getByRole('heading', { name: 'Check your inbox.' })).toBeVisible(); await page.getByLabel('Verification code').fill(await code(email)); await page.getByRole('button', { name: 'Verify & sign in' }).click();
    await expect(page.getByRole('heading', { name: /Welcome back/ })).toBeVisible();
    return { page, context, errors };
  }
  async function navigate(page, name) {
    const mobileButton = page.getByRole('button', { name: 'Open navigation' });
    if (await mobileButton.isVisible()) await mobileButton.click();
    await page.locator('nav').getByRole('button', { name, exact: false }).click();
  }
  async function post(page, path, body) {
    return await page.evaluate(async ({ path, body }) => { for(let attempt=0;attempt<2;attempt++){const csrf=await (await fetch('/api/auth/csrf')).json();const response=await fetch(`/api${path}`,{method:'POST',headers:{'Content-Type':'application/json','X-XSRF-TOKEN':csrf.token},body:JSON.stringify(body)});const result=await response.json();if(response.ok)return result;if(response.status!==403||attempt===1)throw new Error(result.message);} }, { path, body });
  }
  const admin = await signIn('admin@hostelcc.local');
  const a = admin.page;
  await navigate(a, 'Hostel blocks'); await a.getByRole('button', { name: 'Add block', exact: true }).click();
  await a.getByLabel('Block name', { exact: true }).fill('North House'); await a.getByRole('button', { name: 'Save changes' }).click(); await expect(a.getByRole('cell', { name: 'North House', exact: true })).toBeVisible();
  const snapshot = await a.evaluate(async () => (await fetch('/api/workspace')).json()); const block = snapshot.blocks.find(b => b.name === 'North House').id;
  const blockB = (await post(a, '/blocks', { name: 'South House' })).id;
  const room = (await post(a, '/rooms', { blockId: block, number: '101', capacity: 2, roomType: 'NON_AC' })).id;
  const mess = (await post(a, '/messes', { name: 'Garden Dining', capacity: 100, blockIds: [block, blockB] })).id;
  const storage = (await post(a, '/storage-rooms', { blockId: block, name: 'Chair room', itemType: 'CHAIR', capacity: 20, tokenStart: 501, tokenEnd: 520 })).id;
  const student = (await post(a, '/users', { name: 'Ananya Rao', email: 'student@example.test', role: 'STUDENT', rollNo: 'TEST001', blockId: block, roomId: room, messId: mess, active: true, cloakroomAccess: true, messChangeAccess: true })).id;
  const supervisor = (await post(a, '/users', { name: 'Gate Supervisor', email: 'supervisor@example.test', role: 'SUPERVISOR', active: true })).id;
  const house = (await post(a, '/users', { name: 'Cloakroom Staff', email: 'house@example.test', role: 'HOUSEKEEPING', active: true })).id;
  const warden = (await post(a, '/users', { name: 'Mess Warden', email: 'messwarden@example.test', role: 'WARDEN', active: true })).id;
  await post(a, '/scopes', { userId: supervisor, book: 'OUTINGS', targetId: block, active: true });
  await post(a, '/scopes', { userId: house, book: 'CLOAKROOM', targetId: storage, active: true });
  await post(a, '/scopes', { userId: warden, book: 'MESS', targetId: mess, active: true });
  await post(a, '/announcements', { title: 'Welcome to North House', body: 'Your hostel team is here to help. Check your weekly menu and keep your item passes ready.', audience: 'ALL', level: 'INFO', blockId: block });
  await post(a, '/menus', { messId: mess, day: 'MON', breakfast: 'Idli, sambar and fresh fruit', lunch: 'Rice, dal, seasonal vegetables and curd', snacks: 'Tea and vegetable sandwiches', dinner: 'Chapati, paneer and salad' });
  await a.getByRole('button', { name: 'Refresh records' }).click(); await navigate(a, 'Overview'); await a.screenshot({ path: 'test-results/admin-overview.png', fullPage: true });
  await navigate(a, 'Duty books'); await expect(a.getByRole('cell', { name: 'OUTINGS', exact: false }).first()).toBeVisible();
  const s = await signIn('student@example.test', true);
  await navigate(s.page, 'Outings & leave'); await s.page.getByRole('button', { name: 'Request outing / leave' }).click();
  await s.page.getByLabel('Request type').selectOption('OUTING'); await s.page.getByLabel('Destination').fill('Campus library'); await s.page.getByLabel('Reason').fill('Group study');
  const local = d => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  await s.page.getByLabel('Departure', { exact: true }).fill(local(new Date())); await s.page.getByLabel('Expected return').fill(local(new Date(Date.now() + 3600000)));
  await s.page.getByRole('button', { name: 'Save changes' }).click(); await expect(s.page.getByRole('cell', { name: 'Campus library', exact: true })).toBeVisible();
  const sup = await signIn('supervisor@example.test'); await navigate(sup.page, 'Outings & leave');
  for (const action of ['Approve', 'Record exit', 'Record entry']) { await sup.page.getByRole('button', { name: action, exact: true }).click(); await sup.page.getByRole('button', { name: 'Confirm', exact: true }).click(); await expect(sup.page.getByRole('dialog')).not.toBeVisible(); }
  await expect(sup.page.getByRole('cell', { name: 'Returned', exact: true })).toBeVisible();
  await expect(sup.page.locator('nav').getByRole('button', { name: 'Discipline' })).toHaveCount(0);
  await navigate(s.page, 'Cloakroom'); await s.page.getByRole('button', { name: 'Generate item pass' }).click(); await s.page.getByLabel('Room and item type', { exact: true }).selectOption(storage); await s.page.getByRole('button', { name: 'Save changes' }).click();
  await s.page.getByRole('button', { name: 'Passes', exact: true }).click(); await s.page.getByRole('button', { name: 'Open pass' }).click();
  const qr = await s.page.locator('dialog code').textContent(); expect(qr).toMatch(/^HCC1:/); await s.page.screenshot({ path: 'test-results/student-item-pass-mobile.png', fullPage: true });
  await s.page.getByRole('button', { name: 'Close dialog' }).click();
  const h = await signIn('house@example.test'); await navigate(h.page, 'Cloakroom'); await h.page.getByRole('button', { name: 'Scan item pass', exact: true }).click();
  await h.page.getByLabel('Cloakroom', { exact: true }).selectOption(storage); await h.page.getByLabel('Item-pass code').fill(qr); await h.page.getByRole('button', { name: 'Check in & issue token' }).click(); await expect(h.page.getByRole('heading', { name: 'Token 501' })).toBeVisible();
  await expect(h.page.locator('nav').getByRole('button', { name: 'People' })).toHaveCount(0);
  await h.page.screenshot({ path: 'test-results/cloakroom-receipt.png', fullPage: true });
  const mw = await signIn('messwarden@example.test'); await navigate(mw.page, 'Mess & dining'); await mw.page.getByRole('button', { name: 'Polls', exact: true }).click(); await mw.page.getByRole('button', { name: 'Create poll' }).click();
  await mw.page.getByLabel('Mess', { exact: true }).selectOption(mess); await mw.page.getByLabel('Question').fill('Friday dinner choice'); await mw.page.getByLabel('Closes at').fill(local(new Date(Date.now() + 86400000))); await mw.page.getByLabel('Options, one per line').fill('Dosa\nChapati'); await mw.page.getByRole('button', { name: 'Save changes' }).click(); await expect(mw.page.getByRole('heading', { name: 'Friday dinner choice' })).toBeVisible();
  await mw.page.getByRole('button', { name: 'Disable voting' }).click(); await expect(mw.page.getByRole('button', { name: 'Enable voting' })).toBeVisible();
  await expect(mw.page.locator('nav').getByRole('button', { name: 'Outings & leave' })).toHaveCount(0);
  await post(a, '/discipline', { studentId: student, violation: 'Quiet-hours reminder', actionTaken: 'Verbal reminder', notes: 'Synthetic test record', cardHeld: true });
  await s.page.getByRole('button', { name: 'Refresh records' }).click(); await navigate(s.page, 'Discipline'); await expect(s.page.getByRole('cell', { name: 'Quiet-hours reminder', exact: true })).toBeVisible();
  const cookies = await s.context.cookies(); expect(cookies.find(c => c.name === 'HOSTELCC_SESSION').httpOnly).toBe(true);
  expect(await s.page.evaluate(() => Object.keys(localStorage))).toEqual([]);
  await navigate(a, 'People'); await a.getByRole('button', { name: 'Import CSV', exact: true }).click();
  const csv = 'name,email,rollNo,block,room,mess,phone,cloakroomAccess,messChangeAccess\n' + Array.from({ length: 40 }, (_, i) => `Imported Student ${String(i).padStart(3, '0')},import${i}@example.test,IMPORT${i},North House,,Garden Dining,,false,false`).join('\n');
  await a.getByLabel('Student CSV', { exact: true }).setInputFiles({ name: 'students.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) });
  await a.getByRole('button', { name: 'Validate file' }).click(); await expect(a.getByRole('button', { name: 'Import 40 students' })).toBeVisible();
  await a.getByRole('button', { name: 'Import 40 students' }).click(); await expect(a.getByRole('dialog')).not.toBeVisible();
  await a.getByLabel('Search records', { exact: true }).fill('Imported Student'); await expect(a.getByText('40 records · Page 1 of 2')).toBeVisible();
  await a.getByRole('button', { name: 'Next page', exact: true }).click(); await expect(a.getByRole('cell', { name: 'Imported Student 039', exact: true })).toBeVisible();
  await a.getByLabel('Search records', { exact: true }).fill('IMPORT39'); await expect(a.getByText('1 records · Page 1 of 1')).toBeVisible();
  await navigate(a, 'Discipline'); await a.getByRole('button', { name: 'Record incident' }).click();
  await a.getByLabel('Search student', { exact: true }).fill('IMPORT39'); await a.getByLabel('Student', { exact: true }).selectOption({ label: 'Imported Student 039 · IMPORT39 · North House' });
  await a.getByLabel('Violation', { exact: true }).fill('Bulk lookup regression'); await a.getByLabel('Action taken').fill('Reminder'); await a.getByRole('button', { name: 'Save changes' }).click();
  await expect(a.getByRole('cell', { name: 'Bulk lookup regression', exact: true })).toBeVisible();
  for (const client of [admin, s, sup, h, mw]) { expect(client.errors).toEqual([]); await client.context.close(); }
});
