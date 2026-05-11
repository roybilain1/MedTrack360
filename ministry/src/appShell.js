export const DEFAULT_VIEW_ID = 'registry'

export const APP_VIEW_IDS = ['registry', 'monitoring', 'governance', 'announcements', 'settings']

export function resolveAppViewId(viewId) {
  return APP_VIEW_IDS.includes(viewId) ? viewId : DEFAULT_VIEW_ID
}