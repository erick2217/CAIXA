import { useCallback, useEffect, useState } from 'react'
import { Check, ChevronDown, LoaderCircle, Plus, Shield, Trash2, Users } from 'lucide-react'

const roles={admin:'Administrador',financeiro:'Financeiro',operador:'Operador',leitura:'Somente leitura'}
const roleOptions=Object.entries(roles)

export default function MembersModule({supabase,onRoleChange,online=true}){
 const [organizations,setOrganizations]=useState([]),[organizationId,setOrganizationId]=useState(''),[members,setMembers]=useState([])
 const [email,setEmail]=useState(''),[role,setRole]=useState('operador'),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true)
 const [error,setError]=useState(''),[success,setSuccess]=useState('')
 const organization=organizations.find(item=>item.id===organizationId)||organizations[0]
 const canManage=organization?.role==='admin'

 const load=useCallback(async()=>{
  setLoading(true);setError('')
  const {data:orgs,error:orgError}=await supabase.rpc('get_my_organizations')
  if(orgError){setError(orgError.message);setLoading(false);return}
  const list=orgs||[];setOrganizations(list)
  const selected=list.find(item=>item.is_default)||list[0]
  setOrganizationId(selected?.id||'')
  onRoleChange?.(selected?.role||'')
  if(selected){const {data:rows,error:memberError}=await supabase.rpc('list_organization_members');if(memberError)setError(memberError.message);else setMembers(rows||[])}
  else setMembers([])
  setLoading(false)
 },[supabase,onRoleChange])
 useEffect(()=>{load()},[load])

 async function switchOrganization(id){if(!online){setError('Sem conexão. Conecte-se para trocar de organização.');return}setBusy(true);setError('');const {error:e}=await supabase.rpc('set_default_organization',{p_organization_id:id});if(e)setError(e.message);else{setOrganizationId(id);await load()}setBusy(false)}
 async function addMember(e){e.preventDefault();if(!online){setError('Sem conexão. Conecte-se para enviar o convite.');return}setBusy(true);setError('');setSuccess('');const {data,error:e2}=await supabase.functions.invoke('invite-member',{body:{email:email.trim(),role}});if(e2)setError(e2.message);else{setEmail('');setSuccess(data?.message||'Convite processado.');await load()}setBusy(false)}
 async function updateRole(member,nextRole){if(!online){setError('Sem conexão. Conecte-se para alterar permissões.');return}setBusy(true);setError('');const {error:e}=await supabase.rpc('set_organization_member_role',{p_member_id:member.id,p_role:nextRole});if(e)setError(e.message);else{setSuccess('Permissão atualizada.');await load()}setBusy(false)}
 async function remove(member){if(!online){setError('Sem conexão. Conecte-se para remover acessos.');return}if(!window.confirm(`Remover ${member.email} da organização? O histórico financeiro será preservado.`))return;setBusy(true);setError('');const {error:e}=await supabase.rpc('remove_organization_member',{p_member_id:member.id});if(e)setError(e.message);else{setSuccess('Acesso removido.');await load()}setBusy(false)}

 return <>
  <section className="page-heading"><div><span className="eyebrow">ACESSO À SOCIEDADE</span><h1>Equipe e permissões<span>.</span></h1><p>Controle quem pode consultar e operar os dados financeiros.</p></div><span className="count-pill"><Shield size={14}/> Acesso por função</span></section>
  {error&&<div className="mod-notice">{error}</div>}{success&&<div className="mod-notice success">{success}</div>}{!online&&<div className="mod-notice" role="status">Sem conexão. Você pode consultar, mas as alterações exigem internet.</div>}
  <section className="mod-card member-org-card"><div className="mod-card-head"><div><span className="pax-eyebrow">ORGANIZAÇÃO ATIVA</span><h2>{organization?.name||'Organização'}</h2><p>Trocar de organização atualiza os dados mostrados nos módulos.</p></div>{organizations.length>1&&<label className="member-org-select"><span>Organização</span><select value={organizationId} onChange={e=>switchOrganization(e.target.value)} disabled={busy||!online}>{organizations.map(org=><option key={org.id} value={org.id}>{org.name} · {roles[org.role]}</option>)}</select><ChevronDown size={14}/></label>}</div></section>
  {canManage&&<section className="mod-card"><div className="mod-card-head"><div><span className="pax-eyebrow">NOVO ACESSO</span><h2>Convidar membro</h2><p>Contas existentes são adicionadas na hora; novos usuários recebem convite do Supabase Auth.</p></div></div><form className="member-add-form" onSubmit={addMember}><label className="field">E-mail do membro<input type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="pessoa@empresa.com.br"/></label><label className="field">Permissão<select value={role} onChange={e=>setRole(e.target.value)}>{roleOptions.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label><button className="primary-button" disabled={busy||!online}><Plus size={15}/> Enviar convite</button></form></section>}
  <section className="mod-card"><div className="mod-card-head"><div><span className="pax-eyebrow">MEMBROS COM ACESSO</span><h2>Usuários da organização</h2><p>Remover um acesso não apaga os registros da sociedade.</p></div><span className="count-pill"><Users size={14}/> {members.length} membros</span></div>
   {loading?<div className="mod-empty"><LoaderCircle size={18}/> Carregando membros...</div>:members.length===0?<div className="mod-empty"><Users size={22}/><b>Nenhum membro encontrado</b></div>:<div className="mod-table"><table><thead><tr><th>USUÁRIO</th><th>PERMISSÃO</th><th>ACESSO</th></tr></thead><tbody>{members.map(member=><tr key={member.id}><td><span className="mod-person"><i><Users size={15}/></i><b>{member.email}</b></span></td><td>{canManage?<select className="member-role-select" value={member.role} disabled={busy||!online} onChange={e=>updateRole(member,e.target.value)}>{roleOptions.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select>:roles[member.role]}</td><td>{member.is_default?<span className="mod-pill saved"><i/><Check size={12}/> Organização atual</span>:<span className="count-pill">Membro</span>}{canManage&&<button className="service-deactivate" disabled={busy||!online} onClick={()=>remove(member)} aria-label={`Remover ${member.email}`}><Trash2 size={14}/> Remover</button>}</td></tr>)}</tbody></table></div>}
  </section>
  <section className="mod-card member-permissions"><h2>O que cada permissão pode fazer</h2><div className="member-role-grid">{roleOptions.map(([key,label])=><article key={key}><b>{label}</b><span>{key==='admin'?'Acesso completo, equipe, reabertura e configurações.':key==='financeiro'?'Caixa, cobradores, folha, serviços e relatórios.':key==='operador'?'Lançar movimentações e valores dos cobradores; consultar o caixa.':'Somente consultar os módulos liberados.'}</span></article>)}</div></section>
 </>
}
