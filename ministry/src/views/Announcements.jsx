import { useCallback, useEffect, useState } from 'react'
import { Megaphone, RefreshCw, Send, Archive, AlertTriangle } from 'lucide-react'
import { announcementsApi } from '../services/monitoringApi.js'

const MAX_TITLE = 255
const MAX_BODY = 4000

function formatDateTime(value) {
  if (!value) return '—'
  const dt = new Date(value)
  if (Number.isNaN(dt.getTime())) return '—'
  return dt.toLocaleString()
}

export default function Announcements() {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [audience, setAudience] = useState('both')
  const [includeInactive, setIncludeInactive] = useState(false)
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)
  const [statusMessage, setStatusMessage] = useState(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await announcementsApi.list({ includeInactive })
      setItems(Array.isArray(res?.data) ? res.data : [])
    } catch (e) {
      setError(e.message || 'Failed to load announcements')
    } finally {
      setLoading(false)
    }
  }, [includeInactive])

  useEffect(() => {
    load()
  }, [load])

  async function handleSubmit(event) {
    event.preventDefault()
    setStatusMessage(null)
    setError(null)
    const trimmedTitle = title.trim()
    const trimmedBody = body.trim()
    if (!trimmedTitle || !trimmedBody) {
      setError('Title and body are required.')
      return
    }
    setSubmitting(true)
    try {
      await announcementsApi.create({ title: trimmedTitle, body: trimmedBody, audience })
      setTitle('')
      setBody('')
      setAudience('both')
      const targetLabel = audience === 'pos' ? 'pharmacy POS apps' : audience === 'mobile' ? 'mobile citizen app' : 'all apps (mobile + POS)'
      setStatusMessage(`Announcement posted to ${targetLabel}.`)
      await load()
    } catch (e) {
      setError(e.message || 'Failed to post announcement')
    } finally {
      setSubmitting(false)
    }
  }

  async function handleDeactivate(id) {
    setError(null)
    setStatusMessage(null)
    try {
      await announcementsApi.deactivate(id)
      setStatusMessage('Announcement deactivated.')
      await load()
    } catch (e) {
      setError(e.message || 'Failed to deactivate')
    }
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-xl bg-slate-800 flex items-center justify-center mt-0.5">
            <Megaphone size={17} className="text-teal-400" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-slate-800">Announcements</h1>
            <p className="text-sm text-slate-500 mt-0.5">
              Post a message that all pharmacy apps will read on their next sync.
            </p>
          </div>
        </div>
        <button
          onClick={load}
          className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-teal-700 bg-teal-50 border border-teal-200 rounded-lg hover:bg-teal-100"
        >
          <RefreshCw size={12} />
          Refresh
        </button>
      </div>

      <form
        onSubmit={handleSubmit}
        className="bg-white border border-slate-200 rounded-xl p-5 space-y-4 shadow-sm"
      >
        <div>
          <label className="text-xs font-semibold text-slate-600 uppercase tracking-wide">
            Title
          </label>
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={MAX_TITLE}
            placeholder="e.g. Updated pricing policy effective May 10"
            className="mt-1 w-full px-3 py-2 text-sm border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500"
          />
          <div className="text-[11px] text-slate-400 mt-1">
            {title.length}/{MAX_TITLE}
          </div>
        </div>
        <div>
          <label className="text-xs font-semibold text-slate-600 uppercase tracking-wide">
            Message
          </label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            maxLength={MAX_BODY}
            rows={5}
            placeholder="Write the message that pharmacies will see…"
            className="mt-1 w-full px-3 py-2 text-sm border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 resize-y"
          />
          <div className="text-[11px] text-slate-400 mt-1">
            {body.length}/{MAX_BODY}
          </div>
        </div>
        <div>
          <label className="text-xs font-semibold text-slate-600 uppercase tracking-wide">
            Send to
          </label>
          <div className="mt-1 flex gap-2">
            {[
              { key: 'both',   label: 'Both apps',     hint: 'Citizens + Pharmacies' },
              { key: 'mobile', label: 'Citizen app',   hint: 'Mobile only' },
              { key: 'pos',    label: 'Pharmacy POS',  hint: 'POS terminals only' },
            ].map((opt) => {
              const active = audience === opt.key
              return (
                <button
                  key={opt.key}
                  type="button"
                  onClick={() => setAudience(opt.key)}
                  className={`flex-1 text-left px-3 py-2 rounded-lg border text-xs transition-colors ${
                    active
                      ? 'bg-teal-50 border-teal-300 ring-2 ring-teal-200 text-teal-800'
                      : 'bg-white border-slate-300 hover:bg-slate-50 text-slate-700'
                  }`}
                >
                  <div className="font-semibold">{opt.label}</div>
                  <div className="text-[10px] text-slate-500 mt-0.5">{opt.hint}</div>
                </button>
              )
            })}
          </div>
        </div>
        {error && (
          <div className="flex items-start gap-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
            <AlertTriangle size={14} className="mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}
        {statusMessage && (
          <div className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2">
            {statusMessage}
          </div>
        )}
        <div className="flex justify-end">
          <button
            type="submit"
            disabled={submitting}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-teal-600 rounded-lg hover:bg-teal-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Send size={14} />
            {submitting ? 'Posting…' : 'Post announcement'}
          </button>
        </div>
      </form>

      <div className="bg-white border border-slate-200 rounded-xl p-5 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-sm font-semibold text-slate-800">Recent announcements</h2>
          <label className="inline-flex items-center gap-2 text-xs text-slate-600">
            <input
              type="checkbox"
              checked={includeInactive}
              onChange={(e) => setIncludeInactive(e.target.checked)}
              className="rounded border-slate-300"
            />
            Show deactivated
          </label>
        </div>

        {loading ? (
          <div className="text-sm text-slate-500 text-center py-8">Loading…</div>
        ) : items.length === 0 ? (
          <div className="text-sm text-slate-500 text-center py-8">No announcements yet.</div>
        ) : (
          <ul className="space-y-3">
            {items.map((item) => (
              <li
                key={item.id}
                className={`border rounded-lg p-4 ${
                  item.is_active ? 'border-slate-200 bg-white' : 'border-slate-200 bg-slate-50 opacity-70'
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <h3 className="text-sm font-semibold text-slate-800 truncate">
                        {item.title}
                      </h3>
                      {(() => {
                        const aud = item.audience || 'both'
                        const audCls = aud === 'pos'
                          ? 'bg-indigo-50 text-indigo-700 border-indigo-200'
                          : aud === 'mobile'
                            ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                            : 'bg-teal-50 text-teal-700 border-teal-200'
                        const audLabel = aud === 'pos' ? 'Pharmacy POS' : aud === 'mobile' ? 'Citizen app' : 'Both apps'
                        return (
                          <span className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded border ${audCls}`}>
                            {audLabel}
                          </span>
                        )
                      })()}
                      {!item.is_active && (
                        <span className="text-[10px] font-semibold text-slate-500 bg-slate-200 px-1.5 py-0.5 rounded">
                          DEACTIVATED
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-slate-600 mt-1 whitespace-pre-wrap break-words">
                      {item.body}
                    </p>
                    <div className="text-[11px] text-slate-400 mt-2">
                      Posted {formatDateTime(item.created_at)}
                    </div>
                  </div>
                  {item.is_active && (
                    <button
                      onClick={() => handleDeactivate(item.id)}
                      className="shrink-0 inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-slate-700 bg-slate-100 border border-slate-200 rounded-lg hover:bg-slate-200"
                      title="Deactivate so pharmacies stop seeing this"
                    >
                      <Archive size={12} />
                      Deactivate
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
