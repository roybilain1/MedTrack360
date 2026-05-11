import { useState } from 'react'
import Sidebar from './components/Sidebar'
import MasterRegistry from './views/MasterRegistry'
import Settings from './views/Settings'
import ComplianceMonitoring from './views/ComplianceMonitoring'
import Announcements from './views/Announcements'
import SystemGovernance from './views/SystemGovernance'
import { DEFAULT_VIEW_ID, resolveAppViewId } from './appShell.js'

const VIEWS = {
  registry: MasterRegistry,
  monitoring: ComplianceMonitoring,
  governance: SystemGovernance,
  announcements: Announcements,
  settings: Settings,
}

function App() {
  const [activeView, setActiveView] = useState(DEFAULT_VIEW_ID)

  const resolvedView = resolveAppViewId(activeView)

  const ActiveComponent = VIEWS[resolvedView] || VIEWS[DEFAULT_VIEW_ID]

  function handleNavigate(nextView) {
    setActiveView(resolveAppViewId(nextView))
  }

  return (
    <div
      style={{ fontFamily: "'Inter', ui-sans-serif, system-ui, sans-serif" }}
      className="flex h-screen bg-slate-50 overflow-hidden"
    >
      <Sidebar activeView={resolvedView} onNavigate={handleNavigate} />
      <main className="flex-1 overflow-y-auto overflow-x-hidden">
        <ActiveComponent />
      </main>
    </div>
  )
}

export default App
