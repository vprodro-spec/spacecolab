/* Shared interaction polish. Drafts, prices, permissions and persistence stay in their owners. */
(function(root){
'use strict';
const E=esc,L=root.SCL293,C=root.SCL293Core;
const P=root.SCL306={};
P.searchKey=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('el').replace(/ς/g,'σ').trim();
P.rememberPicker=function(button){
 const picker=button.closest?.('[data-scl306-picker]');if(!picker)return ()=>{};
 const context=picker.dataset.scl306Picker,theme=button.dataset.theme,scroll=picker.querySelector('.scl293-themes')?.scrollTop||0;
 const parents=[];for(let p=picker.parentElement;p;p=p.parentElement)if(p.scrollTop)parents.push([p,p.scrollTop]);
 return ()=>{const next=[...document.querySelectorAll('[data-scl306-picker]')].find(x=>x.dataset.scl306Picker===context);if(!next)return;
  const target=[...next.querySelectorAll('.scl306-theme-select')].find(x=>x.dataset.theme===theme);target?.focus({preventScroll:true});
  const grid=next.querySelector('.scl293-themes');if(grid)grid.scrollTop=scroll;
  for(const [p,top] of parents)if(p.isConnected)p.scrollTop=top;
 };
};
L.picker=function(context,q,current,format,disabled=false,themes=C.available(L.data)){
 const query=P.searchKey(q),rows=themes.filter(t=>P.searchKey(t.title+' '+t.variants.flatMap(v=>C.styles.flatMap(n=>v.setups[n]?.products||[])).join(' ')).includes(query));
 return '<div class="scl306-picker" data-scl306-picker="'+E(context)+'"><div class="scl306-search"><span class="scl306-search-icon" aria-hidden="true"></span><input type="search" data-scl293-search="'+E(context)+'" value="'+E(q||'')+'" placeholder="Βρες θεματική ή προϊόν…" aria-label="Αναζήτηση βιβλιοθήκης" autocomplete="off">'+(q?'<button type="button" class="scl306-clear" data-scl306="clear-search" aria-label="Καθαρισμός αναζήτησης">×</button>':'')+'</div><div class="scl293-themes">'+(rows.length?rows.map(t=>{
  const selected=current===t.id,products=[...new Set(t.variants.flatMap(v=>C.styles.flatMap(n=>v.setups[n]?.products||[])))].slice(0,4).join(' · ');
  return '<article class="scl306-theme'+(selected?' selected':'')+'"><button type="button" class="scl306-theme-select" data-scl293="'+E(context)+'-select" data-theme="'+E(t.id)+'" aria-pressed="'+selected+'" '+(disabled?'disabled':'')+'><span class="scl306-selection" aria-hidden="true">'+(selected?'✓':'')+'</span><span class="scl306-theme-copy"><strong>'+E(t.title)+'</strong><small>'+E(products||'Δεν έχουν οριστεί προϊόντα')+'</small></span></button><div class="scl306-theme-foot"><span class="scl306-selected-label">'+(selected?'Επιλεγμένη':'')+'</span><button type="button" class="scl306-preview" data-scl293="preview" data-theme="'+E(t.id)+'" data-format="'+E(format||'vertical')+'" aria-label="Πλανόγραμμα: '+E(t.title)+'">Πλανόγραμμα <span aria-hidden="true">↗</span></button></div></article>';
 }).join(''):'<p class="scl306-empty" role="status">Δεν βρέθηκε θεματική. Δοκίμασε άλλη λέξη.</p>')+'</div></div>';
};
document.addEventListener('click',e=>{
 const b=e.target.closest?.('[data-scl306="clear-search"]');if(!b)return;e.preventDefault();e.stopImmediatePropagation();
 const field=b.closest('[data-scl306-picker]').querySelector('[data-scl293-search]');field.value='';field.dispatchEvent(new Event('input',{bubbles:true}));
},true);
const style=document.createElement('style');style.id='scl306-polish';style.textContent=`
.scl304{--scl-line:#dce5ed;--scl-soft:#f4f7fb;--scl-accent:#145b95}
.scl304 body{background:#f4f7fa}
.scl304 :is(button,input,select,textarea){transition:background-color .15s,border-color .15s,box-shadow .15s}
.scl304 button:not(:disabled):hover{filter:none}
.scl304 :is(.scl303-btn,.scl231-btn,[data-scl290],[data-scl293],.scl295-btn,.action){border-radius:10px!important;font-weight:600!important}
.scl304 :is(.scl303-btn,.scl231-btn,[data-scl290],[data-scl293],.scl295-btn,.action):not(:disabled):hover{border-color:#91aec6!important;background:#eef5fb}
.scl304 :is(.scl303-btn.primary,.scl231-btn.primary,[data-scl290].primary,.action.blue,.scl293-save button[type=submit]):not(:disabled):hover{background:#104b7c!important;border-color:#104b7c!important}
.scl304 :is(.scl212-tab,.scl295-nav button){border-radius:10px!important;min-height:44px;font-weight:600!important}
.scl304 :is(.scl212-tab,.scl295-nav button):not(.active):hover{background:#edf3f8!important;border-color:#adc2d4!important}
.scl304 :is(.scl295-section,.scl250-panel,.scl250-room,.scl292-panel){border-radius:16px}
.scl304 :is(.scl295-position-card,.scl294-pharmacy,.scl300-month,.scl293-list article){border-radius:13px;background:#fff}
.scl304 .scl295-position-card{box-shadow:0 3px 12px #20344c05}.scl304 .scl295-position-card header{padding-bottom:12px}
.scl304 :is(.scl300-field,.scl293-field,.scl290-fields>label,.field) :is(input:not([type=checkbox]):not([type=radio]),select,textarea){border-color:#c6d3df!important;border-radius:10px!important;min-height:46px}
.scl304 :is(.scl300-field,.scl293-field,.scl290-fields>label,.field)>span{font-weight:600!important;color:#344b62}
.scl304 :is(input,textarea)::placeholder{color:#778a9d;opacity:1}
.scl304 :is(.scl300-field,.scl293-field,.scl290-fields>label,.field) :is(input,select,textarea):focus{border-color:#4687b9!important;box-shadow:0 0 0 3px #145b9514!important;outline:0}
.scl304 :is(.scl300-field,.scl293-field,.scl290-fields>label,.field) textarea{line-height:1.6}
.scl304 input[type=checkbox]{border-radius:5px;cursor:pointer}
.scl304 .scl306-money{position:relative;display:flex;align-items:center;width:min(100%,340px);max-width:100%;font-weight:500!important}
.scl304 .scl306-money input[type=number][inputmode=decimal]{padding:12px 58px 12px 15px!important;min-height:56px!important;font-size:24px!important;font-weight:650!important;line-height:1.2;font-variant-numeric:tabular-nums;appearance:textfield;-moz-appearance:textfield}
.scl304 .scl306-money input::-webkit-inner-spin-button,.scl304 .scl306-money input::-webkit-outer-spin-button{appearance:none;margin:0}
.scl304 .scl306-money .scl306-currency{position:absolute;right:17px;top:50%;transform:translateY(-50%);font-size:21px;font-weight:500;color:#6e8295;pointer-events:none;border-left:1px solid #dce5ed;padding-left:13px}
.scl304 .scl297-form button.scl306-suggestion{display:inline-flex;align-items:center;gap:5px;padding:6px 0!important;background:none!important;color:var(--scl-accent)!important;border:0!important;border-radius:4px!important;min-height:36px;font-size:13px!important;font-weight:500!important;text-align:left}
.scl304 .scl297-form button.scl306-suggestion:hover{text-decoration:underline;text-underline-offset:4px}
.scl304 .scl306-price-help{font-size:12px;color:var(--scl-muted);line-height:1.6!important}
.scl304 :is(.scl297-comparison,.scl300-summary){gap:10px}
.scl304 .scl297-form #scl297DealTotals p{background:#f4f7fb;border:0;padding:16px;border-radius:11px}
.scl304 .scl297-form #scl297DealTotals p:last-child{background:#eef6f4;color:#235b4c}
.scl304 .scl297-comparison strong{font-size:21px;font-variant-numeric:tabular-nums;line-height:1.4}
.scl304 :is(.modal-card,.scl290-dialog,.scl300-overlay>section,.scl295-overlay>section){border-radius:18px!important;box-shadow:0 24px 80px #172d4738!important}
.scl304 .modal>.modal-card{display:flex;flex-direction:column;overflow:hidden;padding:0!important}
.scl304 .modal>.modal-card>.modal-head{position:relative;top:auto;flex:0 0 auto;margin:0;padding:20px 22px;z-index:4}
.scl304 .modal>.modal-card>[id$="ModalBody"]{flex:1 1 auto;min-height:0;overflow:auto;padding:22px;overscroll-behavior:contain}
.scl304 :is(.modal-head,.scl300-dialog-head,.scl290-dialog>header,.scl295-overlay>section>header){align-items:center}
.scl304 :is(.modal-head [data-close],.scl300-dialog-head button,.scl290-dialog>header button){background:#f3f6f9;border:1px solid transparent!important;border-radius:9px;min-height:36px;padding:8px 12px;font-size:12px;flex-shrink:0}
.scl304 :is(.deal-section,.scl300-panel,.scl293-box){border-radius:12px;padding:20px;border-color:#e3eaf0}
.scl304 .deal-section-head{margin-bottom:16px!important}.scl304 .deal-section-title{font-size:16px!important}.scl304 .deal-step{border:0;border-radius:8px;background:#edf3f9}
.scl304 .scl298-position-strip{background:#edf3f9;color:#344e68;padding:10px 14px;font-size:12px;border-radius:9px}
.scl304 .scl299-agreement-status{padding:13px 16px;border-width:0 0 0 3px;border-radius:8px}.scl304 .scl299-agreement-status p{font-size:12px;margin-top:5px}
.scl304 .scl297-form .actionRow{padding:14px 0;gap:9px;bottom:-22px}.scl304 .scl297-form .actionRow button{min-height:42px}
.scl304 .scl297-form button[data-scl297=review-shelf-remove]{color:#9c3939;background:#fff;border-color:#ead3d3!important}
.scl304 .scl297-form .scl297-month{border-radius:11px;padding:10px;background:#fff;gap:9px}.scl304 .scl297-month:has(input:checked){background:#f0f6fc;border-color:#9bbbd4}.scl304 .scl297-month:has(input:disabled){background:#f6f7f9}
.scl304 .scl297-month button{border:0;background:transparent;font-size:13px!important;text-align:left;min-height:34px;padding:3px!important}.scl304 .scl297-month button[aria-pressed=true]{color:var(--scl-accent);text-decoration:underline;text-underline-offset:5px}
.scl304 .scl297-month label{display:flex;align-items:center;gap:7px;cursor:pointer}.scl304 .scl297-month small{color:var(--scl-muted);font-size:11px!important}
.scl304 .scl306-picker{margin-top:16px;min-width:0}
.scl304 .scl306-search{display:flex;align-items:center;position:relative;border:1px solid #c6d3df;border-radius:11px;background:#fff;min-height:46px}
.scl304 .scl306-search:focus-within{border-color:#4687b9;box-shadow:0 0 0 3px #145b9514}
.scl304 .scl306-search input[data-scl293-search]{width:100%;min-width:0;border:0!important;border-radius:11px!important;outline:0!important;box-shadow:none!important;padding:12px 42px!important;font-size:14px;background:transparent}
.scl304 .scl306-search input::-webkit-search-cancel-button{appearance:none}
.scl306-search-icon{position:absolute;left:17px;top:14px;width:12px;height:12px;border:1.7px solid #72899d;border-radius:50%;pointer-events:none;box-sizing:border-box}.scl306-search-icon:after{content:'';position:absolute;width:6px;height:1.7px;background:#72899d;right:-5px;bottom:-3px;transform:rotate(45deg);border-radius:2px}
.scl304 .scl306-clear{position:absolute;right:5px;top:5px;width:35px;height:35px;padding:0;border:0;border-radius:7px;color:#536c82;background:transparent;font-size:24px;line-height:1}
.scl304 .scl306-clear:hover{background:#edf3f9}
.scl304 .scl306-picker .scl293-themes{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;padding:3px;max-height:52vh;scrollbar-width:thin;scrollbar-color:#bdcdda transparent;align-items:stretch;overscroll-behavior:contain}
.scl304 .scl293-themes article.scl306-theme{display:flex;flex-direction:column;padding:0;min-width:0;border:1px solid #dce5ed;border-radius:12px;background:white;overflow:visible}
.scl304 .scl306-theme:has(.scl306-theme-select:not(:disabled)):hover{border-color:#92b4ce;box-shadow:0 3px 12px #20344c08}
.scl304 .scl293-themes article.scl306-theme.selected{background:#f0f6fc;border-color:#6d9fc5;box-shadow:inset 0 0 0 1px #6d9fc5}
.scl304 button.scl306-theme-select[data-scl293]{display:flex;flex:1;align-items:flex-start;gap:12px;width:100%;border:0!important;border-radius:11px 11px 0 0!important;background:transparent!important;color:var(--scl-ink)!important;padding:16px 15px 8px!important;text-align:left;min-height:98px;font-weight:500!important}
.scl304 .scl306-theme-select:disabled{opacity:.6}
.scl304 .scl306-selection{display:flex;align-items:center;justify-content:center;width:20px;height:20px;box-sizing:border-box;border:1.5px solid #b3c5d4;border-radius:50%;flex-shrink:0;margin-top:1px;background:white;font-size:12px;font-weight:700;color:white}
.scl304 .selected .scl306-selection{background:var(--scl-accent);border-color:var(--scl-accent)}
.scl304 .scl306-theme-copy{min-width:0;flex:1}.scl304 .scl306-theme-copy strong{font-size:14px;line-height:1.5;font-weight:650;display:block}.scl304 .scl306-theme-copy small{font-size:12px;line-height:1.6;margin:7px 0 0;color:#61758a;font-weight:400}
.scl304 .scl306-theme-foot{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:0 10px 8px 47px}
.scl304 .scl306-selected-label{font-size:11px;color:var(--scl-accent);font-weight:600}
.scl304 button.scl306-preview[data-scl293]{padding:6px!important;min-height:32px;border:0!important;background:transparent!important;font-size:12px!important;color:var(--scl-accent);border-radius:6px!important}
.scl304 button.scl306-preview:hover{text-decoration:underline;text-underline-offset:3px}.scl304 .scl306-preview span{margin-left:3px}
.scl304 .scl306-empty{grid-column:1/-1;text-align:center;padding:32px 16px;color:var(--scl-muted);background:#f5f8fb;border-radius:10px;font-size:14px}
.scl304 #planogramModal{z-index:100100}
.scl304 #programModal .month-list{gap:7px}.scl304 #programModal .month-item{border:1px solid #dce5ed!important;border-radius:10px!important;background:white;padding:12px!important}.scl304 #programModal .month-item.active{background:#edf5fc!important;border-color:#8db4d3!important;color:var(--scl-accent)}
.scl304 .scl293-list article{padding:18px 20px;align-items:center}.scl304 .scl293-list article:hover{border-color:#b6c9d9}.scl304 .scl293-list .scl293-actions{gap:6px}
.scl304 .scl303-table{border-collapse:separate;border-spacing:0}.scl304 .scl303-table th{background:#f5f8fb;color:#536a7f;font-weight:600;border-bottom:1px solid #dce5ed}.scl304 .scl303-table tbody tr:hover>td{background:#f7fafd}.scl304 .scl303-table td{border-bottom:1px solid #e8edf2;line-height:1.6}.scl304 .scl303-table code{font-variant-numeric:tabular-nums}
.scl304 .scl303-state{border-radius:7px;font-weight:500}.scl304 .scl303-filter-main{padding-bottom:6px}.scl304 .scl303-multi summary strong{border-radius:9px;background:#fff}
.scl304 .scl300-context{background:#edf3f9;color:#344e68;border-radius:10px}.scl304 .scl300-month .scl300-kind{font-size:11px;letter-spacing:.2px;font-weight:600}.scl304 .scl300-campaign,.scl304 .scl300-theme{border-radius:8px}
.scl304 .scl300-scope-list label:hover{background:#f5f9fd}.scl304 .scl300-scope-list label:has(input:checked){background:#edf5fc}
.scl304 .scl305-total{border-radius:12px!important}.scl304 button.scl305-total:hover{background:#f0f6fc!important;border-color:#9dbbd2!important}
@media(max-width:700px){.scl304 .scl306-picker .scl293-themes{grid-template-columns:1fr;max-height:48vh}.scl304 .scl306-money{width:100%}.scl304 .scl306-theme-select{min-height:84px!important}.scl304 .scl297-form .actionRow{bottom:-22px}.scl304 .scl293-list article{padding:15px}.scl304 :is(.deal-section,.scl300-panel,.scl293-box){padding:15px}.scl304 .scl297-form .actionRow .blue{flex-basis:100%;order:2}.scl304 :is(input,select,textarea){font-size:16px!important}.scl304 .scl306-search input[data-scl293-search]{font-size:16px}.scl304 .scl293-themes{overscroll-behavior:auto}}
@media print{.scl304 .modal>.modal-card{display:block;overflow:visible}.scl304 .modal>.modal-card>[id$="ModalBody"]{overflow:visible;max-height:none;padding:0}}
@media(prefers-reduced-motion:reduce){.scl304 :is(button,input,select,textarea){transition:none}}
@media print{.scl304 body{background:white}.scl304 .scl306-clear{display:none}}
`;
document.head.append(style);
})(window);
