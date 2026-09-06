.pragma library
.import "WindowModel.js" as WindowModel

// Layout and Quick Look geometry adapted from omarchy-expose, MIT.
// See LICENSE and UPSTREAM.md in this directory for provenance.

// Entries are sorted once by natural width before testing row counts.
function assignCompositionRows(entries, rowCount) {
    var rows = [];
    for (var i = 0; i < rowCount; i++)
        rows.push({ entries: [], naturalWidth: 0, naturalHeight: 0 });

    for (var entry of entries) {
        var best = rows[0];
        for (var row of rows) {
            if (row.naturalWidth < best.naturalWidth
                    || (row.naturalWidth === best.naturalWidth && row.entries.length < best.entries.length))
                best = row;
        }
        best.entries.push(entry);
        best.naturalWidth += entry.width;
        best.naturalHeight = Math.max(best.naturalHeight, entry.height);
    }
    return rows;
}

// Each row's width and the total height are linear in scale. Solve their
// bounds directly instead of allocating trial layouts in a binary search.
function scaleForRows(rows, width, height, gap, padding, footerHeight) {
    var fixedHeight = footerHeight + padding * 2 + (footerHeight > 0 ? padding : 0);
    var scale = Math.min(width, height);
    var naturalHeight = 0;
    for (var row of rows) {
        var count = row.entries.length;
        scale = Math.min(scale, (width - count * padding * 2 - (count - 1) * gap) / row.naturalWidth);
        naturalHeight += row.naturalHeight;
    }
    return Math.min(scale, (height - rows.length * fixedHeight - (rows.length - 1) * gap) / naturalHeight);
}

function composeRows(rows, scale, width, height, gap, padding, footerHeight) {
    var fixedHeight = footerHeight + padding * 2 + (footerHeight > 0 ? padding : 0);
    var totalHeight = rows.reduce(function(total, row) { return total + row.naturalHeight * scale + fixedHeight; }, 0)
        + (rows.length - 1) * gap;
    var y = (height - totalHeight) / 2;
    var result = [];
    rows.forEach(function(row, rowIndex) {
        row.entries.sort(function(a, b) { return a.index - b.index; });
        var rowWidth = row.naturalWidth * scale + row.entries.length * padding * 2 + (row.entries.length - 1) * gap;
        var rowHeight = row.naturalHeight * scale + fixedHeight;
        var x = (width - rowWidth) / 2;
        row.entries.forEach(function(entry) {
            var cardWidth = entry.width * scale + padding * 2;
            var cardHeight = entry.height * scale + fixedHeight;
            result[entry.index] = {
                x: x,
                y: y + (rowHeight - cardHeight) * ((entry.index + rowIndex) % 3) / 2,
                width: cardWidth,
                height: cardHeight
            };
            x += cardWidth + gap;
        });
        y += rowHeight + gap;
    });
    return result;
}

function computeWindowLayout(toplevels, width, height, gap, padding, footerHeight, viewportRatioHint) {
    return computeLayoutForRatios(toplevels.map(function(top) { return WindowModel.aspectRatioFor(top); }),
        width, height, gap, padding, footerHeight, viewportRatioHint);
}

function computeLayoutForRatios(ratios, width, height, gap, padding, footerHeight, viewportRatioHint) {
    if (!ratios.length || width <= 0 || height <= 0) return [];
    var edgeInset = gap / 2;
    var availableWidth = Math.max(1, width - gap);
    var availableHeight = Math.max(1, height - gap);
    var entries = ratios.map(function(ratio, index) {
        var weight = Math.max(0.72, Math.min(1.28, Math.sqrt(ratio / 1.6)));
        return { index: index, width: Math.sqrt(weight * ratio), height: Math.sqrt(weight / ratio) };
    });
    entries.sort(function(a, b) { return b.width - a.width || a.index - b.index; });

    var minimumCardHeight = footerHeight + padding * 2 + (footerHeight > 0 ? padding : 0) + 1;
    var maxRows = Math.max(1, Math.min(entries.length, Math.floor((availableHeight + gap) / (minimumCardHeight + gap))));
    var totalWidth = entries.reduce(function(total, entry) { return total + entry.width; }, 0);
    var averageHeight = entries.reduce(function(total, entry) { return total + entry.height; }, 0) / entries.length;
    var viewportRatio = Number(viewportRatioHint);
    if (!isFinite(viewportRatio) || viewportRatio <= 0) viewportRatio = availableWidth / availableHeight;
    var balancedRows = Math.round(Math.sqrt(totalWidth / Math.max(0.01, viewportRatio * averageHeight)));
    var minimumRows = Math.max(1, Math.min(maxRows, balancedRows));
    var bestRows = null, bestScale = 0;
    for (var count = minimumRows; count <= maxRows; count++) {
        var rows = assignCompositionRows(entries, count);
        var scale = scaleForRows(rows, availableWidth, availableHeight, gap, padding, footerHeight);
        if (scale > bestScale) { bestRows = rows; bestScale = scale; }
    }
    if (!bestRows) return [];
    var result = composeRows(bestRows, bestScale, availableWidth, availableHeight, gap, padding, footerHeight);
    result.forEach(function(rect) { rect.x += edgeInset; rect.y += edgeInset; });
    return result;
}

function previewRectFor(top, width, height, padding, footerHeight) {
    var ratio = WindowModel.aspectRatioFor(top);
    var maxWidth = width * 0.84;
    var maxHeight = height * 0.78;
    var footerSpacing = footerHeight > 0 ? padding : 0;
    var previewWidth = Math.max(1, Math.min(maxWidth - padding * 2, (maxHeight - footerHeight - padding * 2 - footerSpacing) * ratio));
    var previewHeight = Math.max(1, previewWidth / ratio);
    var cardWidth = previewWidth + padding * 2;
    var cardHeight = previewHeight + footerHeight + padding * 2 + footerSpacing;
    var centerX = width / 2;
    var centerY = height / 2;
    return {
        x: Math.max(padding, Math.min(width - cardWidth - padding, centerX - cardWidth / 2)),
        y: Math.max(padding, Math.min(height - cardHeight - padding, centerY - cardHeight / 2)),
        width: cardWidth,
        height: cardHeight
    };
}

