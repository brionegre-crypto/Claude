(function(){
  var btn=document.getElementById('menu-btn'),drawer=document.getElementById('drawer');
  if(btn&&drawer){btn.addEventListener('click',function(){var open=drawer.hidden;drawer.hidden=!open;btn.setAttribute('aria-expanded',String(open));btn.setAttribute('aria-label',open?'Close menu':'Open menu');});}
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
