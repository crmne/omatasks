.pragma library

// Replacement bars (such as Station) give widgets a shell without serviceFor,
// so the service publishes itself here. Service.qml and BarWidget.qml sit in
// the same directory: a library imported from ui/ would be a separate copy.
var active = null

function publish(service) { active = service }
function current() { return active }
// A retired service must not clear a replacement published during hot reload.
function clear(service) { if (active === service) active = null }
