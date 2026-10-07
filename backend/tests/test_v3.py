import io, time, wave, threading
import pytest
import numpy as np
from PIL import Image
from fastapi.testclient import TestClient
from app.db import objects, users, conversations, messages, one, add, now
from app.seed import seed_demo
from app.runtime import worker_loop,status
from test_api import env,auth,upload,audio

def test_seed_is_idempotent_and_no_answers_leak(env):
    app,c,ids,login,_=env;a=login('alice')
    with app.state.engine.begin() as db:
        before=list(db.execute(objects.select()).all())
    assert seed_demo(app.state.engine,app.state.media)==0
    lessons=c.get('/v1/lessons',headers=auth(a)).json()
    assert len(lessons)==6
    assert all('answer' not in q for x in lessons for q in x['questions'])
    refs=c.get('/v1/references',headers=auth(a)).json()
    assert len(refs)==4 and all(x['technical_demo'] for x in refs)

def test_quiz_and_profile_persist_across_sessions(env):
    _,c,_,login,_=env;a=login('alice');h=auth(a)
    assert c.patch('/v1/profile',headers=h,json={'name':'Talaba Nodira','bio':'Doston o‘rganaman','school':'xorazm'}).status_code==204
    l=c.get('/v1/lessons',headers=h).json()[0]
    r=c.post('/v1/lessons/'+l['id']+'/quiz',headers=h,json={'answers':[0,0]})
    assert r.status_code==200 and r.json()['completed'],r.text
    b=login('alice');assert c.get('/v1/profile',headers=auth(b)).json()['name']=='Talaba Nodira'
    assert c.get('/v1/dashboard',headers=auth(b)).json()['completed_lessons']==1
    assert c.get('/v1/dashboard',headers=auth(login('bob'))).json()['completed_lessons']==0

def test_avatar_validation_isolation_and_delete(env):
    _,c,_,login,_=env;a=login('alice');b=login('bob');h={**auth(a),'Content-Type':'application/octet-stream'}
    assert c.put('/v1/profile/avatar',headers=h,content=b'<svg>bad</svg>').status_code==422
    out=io.BytesIO();Image.new('RGB',(900,600),'red').save(out,'PNG')
    assert c.put('/v1/profile/avatar',headers=h,content=out.getvalue()).status_code==204
    r=c.get('/v1/profile/avatar',headers=auth(a));assert r.status_code==200
    assert Image.open(io.BytesIO(r.content)).size==(512,512)
    assert c.get('/v1/profile/avatar',headers=auth(b)).status_code==404
    assert c.delete('/v1/profile/avatar',headers=auth(a)).status_code==204
    assert c.get('/v1/profile/avatar',headers=auth(a)).status_code==404

def test_student_contacts_teacher_assignment_and_no_idor(env):
    app,c,ids,login,_=env;a=login('alice');b=login('bob');teacher=login('teacher');admin=login('admin')
    assert {x['id'] for x in c.get('/v1/contacts',headers=auth(a)).json()}=={ids['admin']}
    assert c.post('/v1/conversations',headers=auth(a),json={'recipient_id':ids['bob']}).status_code==403
    group=c.post('/v1/admin/groups',headers=auth(admin),json={'title':'Doston guruhi','teacher_id':ids['teacher']}).json()['id']
    c.post('/v1/admin/groups/'+group+'/members',headers=auth(admin),json={'user_id':ids['alice']})
    t=c.post('/v1/conversations',headers=auth(a),json={'recipient_id':ids['teacher']}).json()['id']
    msg={'client_id':'message-once-001','body':'Ustoz, ikkinchi jumlani tekshiring.'}
    first=c.post(f'/v1/conversations/{t}/messages',headers=auth(a),json=msg)
    assert first.status_code==201
    assert c.post(f'/v1/conversations/{t}/messages',headers=auth(a),json=msg).json()==first.json()
    assert c.get(f'/v1/conversations/{t}/messages',headers=auth(b)).status_code==404
    assert len(c.get(f'/v1/conversations/{t}/messages',headers=auth(teacher)).json())==1
    assert c.post(f'/v1/conversations/{t}/messages',headers=auth(teacher),json={'client_id':'teacher-reply-001','body':'Jumlani sekinroq takrorlang.'}).status_code==201
    assert len(c.get(f'/v1/conversations/{t}/messages',headers=auth(a),params={'after':first.json()['id']}).json())==1
    with app.state.engine.begin() as db:
        for x in db.execute(objects.select().where(objects.c.kind=='member')).mappings().all():db.execute(objects.delete().where(objects.c.id==x['id']))
    assert c.get(f'/v1/conversations/{t}/messages',headers=auth(teacher)).status_code==403

def test_real_worker_upload_report_end_to_end(env):
    app,c,_,login,_=env;a=login('alice');h=auth(a)
    asset,_=upload(c,a)
    reference=c.get('/v1/references',headers=h).json()[0]
    # Download the same technical tone and re-upload it to exercise reference decoding and DTW.
    tone=c.get('/v1/assets/'+reference['asset_id']+'/content',headers=h).content
    source,_=upload(c,a,tone)
    r=c.post('/v1/analyses',headers={**h,'Idempotency-Key':'worker-e2e-001'},json={'asset_id':source,'school':reference['school'],'locale':'uz','reference_id':reference['id'],'consent_version':'analysis-v1'})
    assert r.status_code==202,r.text
    stop=threading.Event();worker=threading.Thread(target=worker_loop,args=(app.state.engine,app.state.media,stop));worker.start()
    try:
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            job=c.get('/v1/analyses/'+r.json()['job_id'],headers=h).json()
            if job['status'] in ['completed','failed']:break
            time.sleep(.1)
        assert job['status']=='completed',job
        report=c.get('/v1/reports/'+job['report_id'],headers=h).json()
        assert report['metrics'][0]['score']>=95
        assert report['technical_reference'] and report['quality']['median_pitch_hz']>0
        assert report['quality']['duration_seconds']==12
        assert c.get('/v1/system/status',headers=h).json()['worker_online']
    finally:stop.set();worker.join(5)

def test_delete_removes_avatar_and_redacts_messages(env):
    app,c,ids,login,_=env;a=login('alice');h=auth(a)
    thread=c.post('/v1/conversations',headers=h,json={'recipient_id':ids['admin']}).json()['id']
    c.post(f'/v1/conversations/{thread}/messages',headers=h,json={'client_id':'private-text-001','body':'My private text'})
    out=io.BytesIO();Image.new('RGB',(64,64)).save(out,'PNG')
    c.put('/v1/profile/avatar',headers=h,content=out.getvalue())
    assert c.post('/v1/delete-account',headers=h).status_code==202
    assert not (app.state.media/'avatars'/(ids['alice']+'.jpg')).exists()
    with app.state.engine.connect() as db:
        row=db.execute(messages.select().where(messages.c.sender==ids['alice'])).mappings().first()
        assert row['body']=='[Deleted by account owner]'

def test_standalone_measurements_no_fake_style(env):
    from app.acoustics import evaluate
    app,c,_,login,_=env;a=login('alice');asset,_=upload(c,a)
    with app.state.engine.connect() as db:path=one(db,objects,objects.c.id==asset)['data']['path']
    r=evaluate(path,None,'report-test',{'school':'xorazm','locale':'uz','reference_id':None,'asset_id':asset})
    assert 200<r['quality']['median_pitch_hz']<240
    assert r['quality']['voiced_coverage']>.8
    assert all(x['score'] is None for x in r['metrics'])
    assert 'Etalon tanlanmagan' in r['coach_text']

def test_embedded_worker_lifespan_starts_without_separate_service(env, monkeypatch):
    from app.main import create_app
    from fastapi.testclient import TestClient
    app,_,_,_,_=env
    monkeypatch.setenv('EMBEDDED_WORKER','true')
    live=create_app(str(app.state.engine.url),app.state.media,app.state.settings,testing=False)
    with TestClient(live) as c:
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            health=c.get('/healthz').json()
            if health['analysis']['worker_online']:break
            time.sleep(.05)
        assert health['version']=='0.3.1'
        assert health['analysis']['worker_online'] and health['analysis']['ffmpeg_available']
    live.state.engine.dispose()

def test_compressed_m4a_decodes_and_profile_rejects_blank(env,tmp_path):
    import subprocess
    from app.acoustics import evaluate
    app,c,_,login,_=env;a=login('alice')
    source=tmp_path/'source.wav';source.write_bytes(audio())
    target=tmp_path/'source.m4a'
    subprocess.run(['ffmpeg','-v','error','-i',str(source),'-c:a','aac',str(target)],check=True)
    r=evaluate(str(target),None,'m4a-test',{'school':'xorazm','locale':'uz','reference_id':None,'asset_id':'m4a'})
    assert 200<r['quality']['median_pitch_hz']<240
    assert c.patch('/v1/profile',headers=auth(a),json={'name':'    '}).status_code==422

def test_ai_provider_keys_encrypted_restricted_and_rotatable(env, monkeypatch):
    from app import ai
    app,c,_,login,_=env
    learner=login('alice');admin_login=login('admin')
    path='/v1/admin/ai-provider'; ah=auth(admin_login)
    assert c.get(path,headers=auth(learner)).status_code==403
    assert c.get(path,headers=ah).json()=={'provider':'local','model':'','enabled':False,'key_configured':False}
    invalid=c.put(path,headers=ah,json={'provider':'openai','model':'bad/model','api_key':'secret','enabled':True})
    assert invalid.status_code==422
    saved=c.put(path,headers=ah,json={'provider':'openai','model':'mock-model','api_key':'sk-private-test','enabled':True})
    assert saved.status_code==200 and saved.json()['key_configured'] is True
    assert 'sk-private-test' not in saved.text
    with app.state.engine.connect() as db:
        row=db.execute(ai.objects.select().where(ai.objects.c.id==ai.CONFIG_ID)).mappings().one()
        encrypted=row['data']['api_key_encrypted']
        assert encrypted!='sk-private-test' and 'sk-private-test' not in str(row['data'])
    # An omitted key preserves the encrypted value; explicit clear erases it.
    assert c.put(path,headers=ah,json={'provider':'openai','model':'mock-model','enabled':True}).json()['key_configured']
    assert c.put(path,headers=ah,json={'provider':'openai','model':'mock-model','enabled':False,'clear_api_key':True}).json()['key_configured'] is False
    assert c.get('/v1/admin/ai-provider/test',headers=ah).status_code==405

def test_ai_coach_is_opt_in_fallback_and_sends_no_audio_or_identity(env,monkeypatch):
    from app import ai
    from app.db import add
    app,c,ids,login,_=env
    learner=login('alice');ah=auth(login('admin'));lh=auth(learner)
    report={'id':'r-coach-test','school':'xorazm','metrics':[{'kind':'pitch','score':72,'reason':'estimate'},{'kind':'style','score':None,'reason':'not validated'}],'quality':{'median_pitch_hz':220},'coach_text':'Lokal tavsiya','source_asset_id':'private-audio-path-secret'}
    with app.state.engine.begin() as db:add(db,'report',ids['alice'],report,'r-coach-test')
    fallback=c.post('/v1/reports/r-coach-test/coach-ai',headers=lh).json()
    assert not fallback['enhanced'] and fallback['text']=='Lokal tavsiya'
    c.put('/v1/admin/ai-provider',headers=ah,json={'provider':'gemini','model':'mock-model','api_key':'secret-provider-key','enabled':True})
    sent={}
    def fake(provider,model,key,prompt,*,ping=False):
        sent.update(provider=provider,model=model,key=key,prompt=prompt,ping=ping);return 'Ustoz bilan jumlani takrorlang.'
    monkeypatch.setattr(ai,'_generate',fake)
    enhanced=c.post('/v1/reports/r-coach-test/coach-ai',headers=lh)
    assert enhanced.status_code==200 and enhanced.json()['enhanced'] is True
    assert sent['key']=='secret-provider-key' and not sent['ping']
    assert ids['alice'] not in sent['prompt'] and 'private-audio-path-secret' not in sent['prompt']
    assert 'null' in sent['prompt']
    denied=c.post('/v1/reports/r-coach-test/coach-ai',headers=auth(login('bob')))
    assert denied.status_code==404

def test_ai_provider_admin_test_handles_upstream_failure_without_leaking_key(env,monkeypatch):
    from app import ai
    app,c,_,login,_=env;ah=auth(login('admin'))
    c.put('/v1/admin/ai-provider',headers=ah,json={'provider':'xai','model':'mock-model','api_key':'never-return-this','enabled':True})
    seen={}
    def bad(provider,model,key,prompt,*,ping=False):
        seen['key']=key;raise RuntimeError('upstream error containing secret')
    monkeypatch.setattr(ai,'_generate',bad)
    response=c.post('/v1/admin/ai-provider/test',headers=ah)
    assert response.status_code==502 and response.json()['detail']=='ai_provider_connection_failed'
    assert 'never-return-this' not in response.text and seen['key']=='never-return-this'
