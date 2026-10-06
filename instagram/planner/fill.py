import json, pymupdf
rects=json.load(open('fields.json'))
doc=pymupdf.open('12-week-goal-planner.pdf'); k=0; used=set()

def loops(W,D):
    ws=[W] if W else list(range(1,13))
    ds=[D] if D else list(range(1,8))
    return ws,ds
def count(W,D,kind):
    ws,ds=loops(W,D)
    test="f.value!=''" if kind=='a' else "f.value!='Off'&&f.value!=''"
    return (f"var n=0,ws={ws},ds={ds};for(var a=0;a<ws.length;a++)for(var j=0;j<ds.length;j++)for(var i=1;i<=5;i++)"
            f"{{var f=this.getField('w'+ws[a]+'_d'+ds[j]+'_'+'{kind}'+i);if(f&&{test})n++;}}")
def calc_js(calc,W,D):
    if calc=='planned': return count(W,D,'a')+"event.value=n;"
    if calc=='done':    return count(W,D,'c')+"event.value=n;"
    return ("var p=0,d=0;"+count(W,D,'a')+"p=n;"+count(W,D,'c')+"d=n;"
            "event.value=(p>0)?Math.round(100*d/p)+'%':'';")

for pi,page in enumerate(doc):
    for f in rects[pi]:
        x,y,w,h=[v*0.75 for v in (f['x'],f['y'],f['w'],f['h'])]
        k+=1
        wd=pymupdf.Widget()
        if f['cb']:
            if w>20: x,y,w,h=x+w/2-6,y+h/2-6,12,12
            wd.field_type=pymupdf.PDF_WIDGET_TYPE_CHECKBOX
            wd.border_color=(0.4,0.4,0.4); wd.fill_color=(1,1,1); wd.border_width=0.8
        else:
            wd.field_type=pymupdf.PDF_WIDGET_TYPE_TEXT
            wd.text_font='helv'; wd.text_fontsize=11
            wd.text_color=(1,1,1) if f['cover'] else (0.05,0.05,0.2)
            wd.border_width=0; wd.fill_color=None
            if f.get('ml'):
                wd.field_flags|=pymupdf.PDF_TX_FIELD_IS_MULTILINE
                x,y,w,h=x+3,y+3,w-6,h-4
            if f.get('calc'):
                wd.field_flags|=pymupdf.PDF_FIELD_IS_READ_ONLY
                wd.text_fontsize=16 if h>30 else 11
                wd.text_color=(0.79,0.48,0.07)
                wd.field_value='0' if f['calc']!='score' else ''
                wd.script_calc=calc_js(f['calc'],f['w0'],f['d0'])
        name=f.get('n') or f'p{pi+1}_f{k}'
        assert name not in used,name
        used.add(name); wd.field_name=name
        wd.rect=pymupdf.Rect(x,y,x+w,y+h-1)
        page.add_widget(wd)
for page in doc:
    for w in page.widgets():
        if w.script_calc: doc.xref_set_key(w.xref,'Q','1')
doc.save('12-week-goal-planner-fillable.pdf',garbage=3,deflate=True)
print(k,'fields,',len(doc),'pages')
