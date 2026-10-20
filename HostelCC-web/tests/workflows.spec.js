import { test, expect } from '@playwright/test';

test('admin setup, scoped duties, student outings, item QR check-in and histories', async ({ browser, request }) => {
  async function code(email) {
    for (let attempt = 0; attempt < 40; attempt++) {
      const mailbox = process.env.TEST_MAILBOX_URL || 'http://localhost:8025';
      const box = await (await request.get(mailbox + '/messages')).json();
      const mail = box.messages.find(m => m.To.some(to => to.Address === email));
      if (mail) return mail.Text.match(/\b\d{6}\b/)[0];
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error('No test email received');
  }
  async function signIn(email, mobile = false) {
    const context = await browser.newContext({ viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 1050 } });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto('/'); await expect(page.getByRole('link', { name: 'Download Android APK' })).toHaveAttribute('href', '/downloads/HostelCC.apk'); await expect(page.getByRole('button', { name: /iOS App Store/ })).toBeDisabled(); await page.getByLabel('Email address').fill(email); await page.getByRole('button', { name: 'Send sign-in code' }).click();
    await expect(page.getByRole('heading', { name: 'Check your inbox.' })).toBeVisible(); await page.getByLabel('Verification code').fill(await code(email)); await page.getByRole('button', { name: 'Verify & sign in' }).click();
    await expect(page.getByRole('heading', { name: email === 'caterer@example.test' ? 'Mess' : 'Overview', exact:true })).toBeVisible();
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
  const mess = (await post(a, '/messes', { name: 'Garden Dining', blockIds: [block, blockB] })).id;
  const storage = (await post(a, '/storage-rooms', { blockId: block, name: 'Chair room', itemType: 'CHAIR', capacity: 20, tokenStart: 501, tokenEnd: 520 })).id;
  const student = (await post(a, '/users', { name: 'Ananya Rao', email: 'student@example.test', role: 'STUDENT', rollNo: 'TEST001', blockId: block, roomId: room, messId: mess, active: true, cloakroomAccess: true })).id;
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
  const mw = await signIn('messwarden@example.test'); await navigate(mw.page, 'Mess & dining');
  await mw.page.getByLabel('Caterer',{exact:true}).selectOption(mess);
  await mw.page.getByRole('button', { name: 'Polls', exact: true }).click(); await mw.page.getByRole('button', { name: 'New poll' }).click();
  await mw.page.getByLabel('Title',{exact:true}).fill('Friday dinner choice'); await mw.page.getByLabel('Closes at').fill(local(new Date(Date.now() + 86400000))); await mw.page.getByLabel('Options (one per line)').fill('Dosa\nChapati'); await mw.page.getByRole('button', { name: 'Save changes' }).click(); await expect(mw.page.getByRole('heading', { name: 'Friday dinner choice' })).toBeVisible();
  await mw.page.getByLabel('Open',{exact:true}).uncheck(); await expect(mw.page.getByLabel('Open',{exact:true})).not.toBeChecked();
  await expect(mw.page.locator('nav').getByRole('button', { name: 'Outings & leave' })).toHaveCount(0);
  await post(a, '/discipline', { studentId: student, violation: 'Quiet-hours reminder', actionTaken: 'Verbal reminder', notes: 'Synthetic test record', cardHeld: true });
  await s.page.getByRole('button', { name: 'Refresh records' }).click(); await navigate(s.page, 'Discipline'); await expect(s.page.getByRole('cell', { name: 'Quiet-hours reminder', exact: true })).toBeVisible();
  const cookies = await s.context.cookies(); expect(cookies.find(c => c.name === 'HOSTELCC_SESSION').httpOnly).toBe(true);
  expect(await s.page.evaluate(() => Object.keys(localStorage))).toEqual([]);
  await navigate(a, 'People'); await a.getByRole('button', { name: 'Import CSV', exact: true }).click();
  const csv = 'name,email,rollNo,block,room,mess,phone,cloakroomAccess\n' + Array.from({ length: 40 }, (_, i) => `Imported Student ${String(i).padStart(3, '0')},import${i}@example.test,IMPORT${i},North House,,Garden Dining,,false`).join('\n');
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
  await navigate(a,'Floor plans'); await a.getByLabel('Block',{exact:true}).selectOption(block); await a.getByRole('button',{name:'Add floor',exact:true}).click();
  await a.getByLabel('Floor name',{exact:true}).fill('Ground floor'); await a.getByRole('button',{name:'Add element',exact:true}).click();
  await a.getByLabel('Room',{exact:true}).selectOption(room); await a.getByRole('button',{name:'Save floor',exact:true}).click();
  await expect(a.getByRole('button',{name:'Room 101',exact:true})).toBeVisible(); await a.getByRole('button',{name:'Room 101',exact:true}).click();
  await a.getByRole('button',{name:/Ananya Rao/}).click(); await expect(a.getByRole('heading',{name:'Ananya Rao',exact:true})).toBeVisible();
  await expect(a.getByText('Caterer: Garden Dining')).toBeVisible(); await a.getByRole('button',{name:'Close dialog'}).click();
  await navigate(sup.page,'Entry / exit'); await sup.page.getByRole('button',{name:'Add entry / exit'}).click(); await sup.page.getByLabel('Student',{exact:true}).selectOption(student); await sup.page.getByRole('button',{name:'Save changes'}).click(); await expect(sup.page.getByRole('cell',{name:'EXIT',exact:true})).toBeVisible();
  await mw.page.getByRole('button',{name:'Rate food',exact:true}).click(); await mw.page.getByLabel('Accept feedback',{exact:true}).check();
  await mw.page.getByRole('button',{name:'New session'}).click(); await mw.page.getByLabel('Title',{exact:true}).fill('Lunch session'); await mw.page.getByLabel('Opens at').fill(local(new Date(Date.now()-60000))); await mw.page.getByLabel('Closes at').fill(local(new Date(Date.now()+3600000))); await mw.page.getByLabel('Food items (one per line)').fill('Rice\nDal'); await mw.page.getByRole('button',{name:'Save changes'}).click(); await expect(mw.page.getByRole('heading',{name:'Lunch session'})).toBeVisible();
  await navigate(s.page,'Mess & dining'); await s.page.getByRole('button',{name:'Rate food',exact:true}).click(); await s.page.getByRole('button',{name:'Rate this session'}).click(); await s.page.getByLabel('Caterer rating').selectOption('3'); await s.page.getByLabel('Rice',{exact:true}).selectOption('4'); await s.page.getByLabel('Dal',{exact:true}).selectOption('2'); await s.page.getByLabel('Type',{exact:true}).selectOption('COMPLAINT'); await s.page.getByLabel('Comment',{exact:true}).fill('Food was cold'); await s.page.getByRole('button',{name:'Submit feedback'}).click(); await expect(s.page.getByRole('button',{name:'Submitted',exact:true})).toBeDisabled();
  await post(a,'/users',{name:'Caterer representative',email:'caterer@example.test',role:'MESS_MANAGER',messId:mess,active:true});
  const caterer=await signIn('caterer@example.test'); await expect(caterer.page.getByRole('cell',{name:'Food was cold',exact:true})).toBeVisible(); await expect(caterer.page.locator('nav button')).toHaveCount(1); await expect(caterer.page.getByText('Ananya Rao')).toHaveCount(0);
  await mw.page.getByRole('button',{name:'Performance',exact:true}).click(); await expect(mw.page.getByRole('cell',{name:'Rice',exact:true})).toBeVisible(); await expect(mw.page.getByText(/1 responses.*Caterer average 3.00\/5/)).toBeVisible();
  await a.screenshot({path:'test-results/floor-plans.png',fullPage:true});
  await navigate(a,'Reports');await a.getByLabel('Records',{exact:true}).selectOption('users');await a.getByLabel('Name',{exact:true}).check();await a.getByLabel('Email',{exact:true}).check();await a.getByLabel('Search',{exact:true}).fill('Imported Student');await a.getByRole('button',{name:'Build report'}).click();await expect(a.getByRole('cell',{name:'Imported Student 039',exact:true})).toBeVisible();
  const reportDownload=a.waitForEvent('download');await a.getByRole('button',{name:'Export CSV / Excel'}).click();await (await reportDownload).saveAs('test-results/student-report.csv');await a.pdf({path:'test-results/student-report.pdf',format:'A4'}); await mw.page.screenshot({path:'test-results/food-performance.png',fullPage:true});
  for (const client of [admin, s, sup, h, mw, caterer]) { expect(client.errors).toEqual([]); await client.context.close(); }
});

test('Android artifact is served as an APK rather than an HTML fallback', async ({ request }) => {
  test.skip(process.env.EXPECT_APK !== 'true', 'Publish an APK before artifact validation');
  const response = await request.get('/downloads/HostelCC.apk', { headers: { Range: 'bytes=0-3' } });
  expect(response.status()).toBe(206);
  expect(response.headers()['content-type']).toContain('application/vnd.android.package-archive');
  expect((await response.body()).subarray(0, 2).toString()).toBe('PK');
  expect((await request.get('/downloads/missing.apk')).status()).toBe(404);
});
