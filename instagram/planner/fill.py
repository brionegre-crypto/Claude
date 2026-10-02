import json, pymupdf
rects=json.load(open('fields.json'))
doc=pymupdf.open('12-week-goal-planner.pdf'); k=0
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
            wd.text_fontsize=11; wd.text_font='helv'
            wd.text_color=(1,1,1) if f['cover'] else (0.05,0.05,0.2)
            wd.border_width=0; wd.fill_color=None
        wd.field_name=f'p{pi+1}_f{k}'
        wd.rect=pymupdf.Rect(x,y,x+w,y+h-1)
        page.add_widget(wd)
doc.save('12-week-goal-planner-fillable.pdf',garbage=3,deflate=True)
print(k,'fields')
