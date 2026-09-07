import QtQuick

// One cache per output: its consumers share a render context and a texture.
Item {
  id: root
  required property var scheduler
  property real pixelRatio: 1
  property var sources: ({})

  function acquire(toplevel, consumer) {
    var key = String(toplevel.address)
    var source = sources[key]
    if (!source) {
      source = captureComponent.createObject(root, { scheduler: scheduler, toplevel: toplevel })
      sources[key] = source
    }
    if (source.toplevel !== toplevel) source.toplevel = toplevel
    source.consumers = source.consumers.concat([consumer])
    return source
  }
  function release(source, consumer) {
    if (!source) return
    source.consumers = source.consumers.filter(function(view) { return view !== consumer })
    // Let a move attach its destination delegate before evicting the source.
    // Batch releases from one layout update into a single collection.
    if (!source.consumers.length) Qt.callLater(collect)
  }
  function collect() {
    for (var key in sources) {
      var source = sources[key]
      if (source.consumers.length) continue
      delete sources[key]
      source.destroy()
    }
  }
  Component { id: captureComponent; WindowCapture { pixelRatio: root.pixelRatio } }
}
