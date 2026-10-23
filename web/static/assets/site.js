(function(){
  var btn=document.getElementById('menu-btn'),drawer=document.getElementById('drawer');
  if(btn&&drawer){btn.addEventListener('click',function(){var open=drawer.hidden;drawer.hidden=!open;btn.setAttribute('aria-expanded',String(open));btn.setAttribute('aria-label',open?'Close menu':'Open menu');});}
  // Menu dropdowns: hover (desktop) or click/tap to open; Escape, a second click or a click elsewhere closes.
  // "shut" stops a hovered menu from staying visible after it was closed.
  var dds=[].slice.call(document.querySelectorAll('.dd'));
  function setOpen(d,open){var b=d.querySelector('.dd-btn');d.querySelector('.dd-panel').hidden=!open;b.setAttribute('aria-expanded',String(open));d.classList.toggle('shut',!open);}
  function closeAll(except){dds.forEach(function(d){if(d!==except)setOpen(d,false);});}
  dds.forEach(function(d){
    var b=d.querySelector('.dd-btn');
    d.addEventListener('mouseleave',function(){if(b.getAttribute('aria-expanded')!=='true')d.classList.remove('shut');});
    b.addEventListener('click',function(e){e.stopPropagation();var open=b.getAttribute('aria-expanded')!=='true';closeAll(d);setOpen(d,open);});
  });
  document.addEventListener('click',function(e){if(!e.target.closest||!e.target.closest('.dd'))closeAll();});
  document.addEventListener('keydown',function(e){if(e.key==='Escape'){var o=document.querySelector('.dd-btn[aria-expanded="true"]');closeAll();if(o)o.focus();}});
  // Dated menu items (the workshop) disappear after their day, even before the next rebuild.
  var today=new Date().toISOString().slice(0,10);
  document.querySelectorAll('[data-until]').forEach(function(a){if(today>a.getAttribute('data-until'))a.remove();});
  var row=document.getElementById('steps');
  if(row){
    var go=function(dir){var c=row.querySelector('.step');var w=c?c.getBoundingClientRect().width+16:260;row.scrollBy({left:dir*w*2,behavior:'smooth'});};
    var p=document.getElementById('prev'),n=document.getElementById('next');
    if(p)p.addEventListener('click',function(){go(-1)});
    if(n)n.addEventListener('click',function(){go(1)});
  }
  var feat=document.querySelector('.video.feat');
  function player(id){var f=document.createElement('iframe');
    f.src='https://www.youtube-nocookie.com/embed/'+id+'?autoplay=1&rel=0&modestbranding=1';
    f.title='Be The Man video';f.allow='accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
    f.allowFullscreen=true;return f;}
  document.querySelectorAll('[data-yt]').forEach(function(b){
    b.addEventListener('click',function(){
      var id=b.getAttribute('data-yt');
      if(b.classList.contains('feat')||!feat){b.replaceChildren(player(id));b.style.cursor='default';return;}
      feat.replaceChildren(player(id));feat.style.cursor='default';
      var t=document.getElementById('vfeat-title'),m=document.getElementById('vfeat-meta');
      if(t)t.textContent=b.getAttribute('data-title');if(m)m.textContent=b.getAttribute('data-meta');
      document.querySelectorAll('.video.sm').forEach(function(x){x.classList.toggle('now',x===b)});
      feat.scrollIntoView({behavior:'smooth',block:'center'});
    });
  });
})();
