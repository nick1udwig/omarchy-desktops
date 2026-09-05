.pragma library
.import "WindowModel.js" as WindowModel

// Layout and Quick Look geometry adapted from omarchy-expose, MIT.
// See LICENSE and UPSTREAM.md in this directory for provenance.

function assignCompositionRows(entries, rowCount) {
    var rows = [];
    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++)
        rows.push({ entries: [], naturalWidth: 0 });

    var ordered = entries.slice();
    ordered.sort(function (a, b) {
        var widthA = Math.sqrt(a.weight * a.ratio);
        var widthB = Math.sqrt(b.weight * b.ratio);
        if (widthA !== widthB)
            return widthB - widthA;
        return a.index - b.index;
    });

    for (var entryIndex = 0; entryIndex < ordered.length; entryIndex++) {
        var bestRow = 0;
        for (var candidateRow = 1; candidateRow < rows.length; candidateRow++) {
            if (rows[candidateRow].naturalWidth < rows[bestRow].naturalWidth
                    || (rows[candidateRow].naturalWidth === rows[bestRow].naturalWidth
                        && rows[candidateRow].entries.length < rows[bestRow].entries.length))
                bestRow = candidateRow;
        }
        var entry = ordered[entryIndex];
        rows[bestRow].entries.push(entry);
        rows[bestRow].naturalWidth += Math.sqrt(entry.weight * entry.ratio);
    }

    for (var sortRow = 0; sortRow < rows.length; sortRow++)
        rows[sortRow].entries.sort(function (a, b) { return a.index - b.index; });
    return rows;
}

function composeRows(rows, scale, width, height, gap, padding, footerHeight) {
    var measuredRows = [];
    var totalHeight = 0;
    var footerSpacing = footerHeight > 0 ? padding : 0;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        var entries = rows[rowIndex].entries;
        var cards = [];
        var totalWidth = Math.max(0, entries.length - 1) * gap;
        var rowHeight = 0;
        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
            var entry = entries[entryIndex];
            var previewWidth = scale * Math.sqrt(entry.weight * entry.ratio);
            var previewHeight = scale * Math.sqrt(entry.weight / entry.ratio);
            var card = {
                index: entry.index,
                width: previewWidth + padding * 2,
                height: previewHeight + footerHeight + padding * 2 + footerSpacing
            };
            cards.push(card);
            totalWidth += card.width;
            rowHeight = Math.max(rowHeight, card.height);
        }
        if (totalWidth > width || rowHeight > height)
            return null;
        measuredRows.push({ cards: cards, width: totalWidth, height: rowHeight });
        totalHeight += rowHeight;
    }
    totalHeight += Math.max(0, measuredRows.length - 1) * gap;
    if (totalHeight > height)
        return null;

    var verticalGap = measuredRows.length > 1 ? gap : 0;
    var y = (height - totalHeight) / 2;
    var result = [];
    for (var outputRow = 0; outputRow < measuredRows.length; outputRow++) {
        var row = measuredRows[outputRow];
        var horizontalGap = row.cards.length > 1 ? gap : 0;
        var x = (width - row.width) / 2;
        for (var cardIndex = 0; cardIndex < row.cards.length; cardIndex++) {
            var card = row.cards[cardIndex];
            var align = ((card.index + outputRow) % 3) / 2;
            result[card.index] = {
                x: x,
                y: y + (row.height - card.height) * align,
                width: card.width,
                height: card.height
            };
            x += card.width + horizontalGap;
        }
        y += row.height + verticalGap;
    }
    return result;
}

function computeWindowLayout(toplevels, width, height, gap, padding, footerHeight, viewportRatioHint) {
    var count = toplevels.length;
    if (!count || width <= 0 || height <= 0)
        return [];

    var edgeInset = gap / 2;
    var availableWidth = Math.max(1, width - edgeInset * 2);
    var availableHeight = Math.max(1, height - edgeInset * 2);
    var entries = [];
    for (var index = 0; index < count; index++) {
        var ratio = WindowModel.aspectRatioFor(toplevels[index]);
        var adaptiveWeight = Math.max(0.72, Math.min(1.28, Math.sqrt(ratio / 1.6)));
        entries.push({
            index: index,
            ratio: ratio,
            weight: adaptiveWeight,
            extremity: Math.max(ratio, 1 / ratio)
        });
    }
    entries.sort(function (a, b) {
        if (a.extremity !== b.extremity)
            return b.extremity - a.extremity;
        return a.index - b.index;
    });

    var high = Math.min(availableWidth, availableHeight);
    var footerSpacing = footerHeight > 0 ? padding : 0;
    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        var entry = entries[entryIndex];
        high = Math.min(high,
            (availableWidth - padding * 2) / Math.sqrt(entry.weight * entry.ratio),
            (availableHeight - footerHeight - padding * 2 - footerSpacing) / Math.sqrt(entry.weight / entry.ratio));
    }
    high = Math.max(1, high);

    var best = null;
    var bestScale = -1;
    var minimumCardHeight = footerHeight + padding * 2 + footerSpacing + 1;
    var maxRows = Math.max(1, Math.min(count, Math.floor((availableHeight + gap) / (minimumCardHeight + gap))));
    var totalNaturalWidth = 0;
    var totalNaturalHeight = 0;
    for (var naturalIndex = 0; naturalIndex < entries.length; naturalIndex++) {
        totalNaturalWidth += Math.sqrt(entries[naturalIndex].weight * entries[naturalIndex].ratio);
        totalNaturalHeight += Math.sqrt(entries[naturalIndex].weight / entries[naturalIndex].ratio);
    }
    var averageNaturalHeight = totalNaturalHeight / entries.length;
    var viewportRatio = Number(viewportRatioHint);
    if (!isFinite(viewportRatio) || viewportRatio <= 0)
        viewportRatio = availableWidth / availableHeight;
    var balancedRows = Math.round(Math.sqrt(totalNaturalWidth / Math.max(0.01, viewportRatio * averageNaturalHeight)));
    var minimumRows = Math.max(1, Math.min(maxRows, balancedRows));
    for (var rowCount = minimumRows; rowCount <= maxRows; rowCount++) {
        var rows = assignCompositionRows(entries, rowCount);
        var low = 0;
        var rowHigh = high;
        var rowBest = null;
        for (var iteration = 0; iteration < 12; iteration++) {
            var scale = (low + rowHigh) / 2;
            var composed = composeRows(rows, scale, availableWidth, availableHeight, gap, padding, footerHeight);
            if (composed) {
                rowBest = composed;
                low = scale;
            } else {
                rowHigh = scale;
            }
        }
        if (rowBest && low > bestScale) {
            best = rowBest;
            bestScale = low;
        }
    }
    if (!best)
        best = composeRows(assignCompositionRows(entries, 1), 1, availableWidth, availableHeight, gap, padding, footerHeight) || [];
    for (var resultIndex = 0; resultIndex < best.length; resultIndex++) {
        if (!best[resultIndex])
            continue;
        best[resultIndex].x += edgeInset;
        best[resultIndex].y += edgeInset;
    }
    return best;
}

function previewRectFor(top, sourceRect, width, height, padding, footerHeight, placement) {
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
    if (placement === "in-place" && sourceRect) {
        centerX = sourceRect.x + sourceRect.width / 2;
        centerY = sourceRect.y + sourceRect.height / 2;
    }
    return {
        x: Math.max(padding, Math.min(width - cardWidth - padding, centerX - cardWidth / 2)),
        y: Math.max(padding, Math.min(height - cardHeight - padding, centerY - cardHeight / 2)),
        width: cardWidth,
        height: cardHeight
    };
}


