export type Box = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type SliceInput = {
  width: number;
  height: number;
  rows: number;
  cols: number;
  margin: number;
  gutter: number;
  offsetX: number;
  offsetY: number;
};

export type SliceResult = {
  boxes: Box[];
  error?: string;
  warnings: string[];
};

const buildBoundaries = (sizes: number[], marginPx: number): number[] => {
  const boundaries = [marginPx];
  let cursor = marginPx;
  for (let index = 0; index < sizes.length; index += 1) {
    cursor += sizes[index];
    boundaries.push(cursor);
  }
  return boundaries;
};

const applyOffsetToBoundaries = (boundaries: number[], offset: number): number[] => {
  if (!offset || boundaries.length <= 2) {
    return boundaries.slice();
  }
  return boundaries.map((value, index) =>
    index === 0 || index === boundaries.length - 1 ? value : value + offset
  );
};

const offsetCollapseError = (axis: "X" | "Y") =>
  `Offset ${axis} pushes grid lines outside the contact sheet bounds. Reduce the offset or adjust margin/gutter.`;

export function computeBoxes(input: SliceInput): SliceResult {
  const warnings: string[] = [];
  const { width, height, rows, cols, margin, gutter, offsetX, offsetY } = input;

  const marginPx = Math.round(margin);
  const gutterPx = Math.round(gutter);
  const offsetXPx = Math.round(offsetX);
  const offsetYPx = Math.round(offsetY);

  if (width <= 0 || height <= 0) {
    return { boxes: [], error: "Image dimensions are not available yet.", warnings };
  }
  if (rows <= 0 || cols <= 0) {
    return { boxes: [], error: "Rows and columns must be at least 1.", warnings };
  }
  if (margin < 0 || gutter < 0) {
    return { boxes: [], error: "Margin and gutter must be zero or greater.", warnings };
  }

  const usableWidth = width - marginPx * 2 - gutterPx * (cols - 1);
  const usableHeight = height - marginPx * 2 - gutterPx * (rows - 1);
  if (usableWidth <= 0 || usableHeight <= 0) {
    return {
      boxes: [],
      error: "Grid exceeds the image bounds. Reduce margin/gutter or grid size.",
      warnings
    };
  }

  const cellWidthBase = Math.floor(usableWidth / cols);
  const cellHeightBase = Math.floor(usableHeight / rows);
  const cellWidthRemainder = usableWidth - cellWidthBase * cols;
  const cellHeightRemainder = usableHeight - cellHeightBase * rows;
  const colWidths = Array.from({ length: cols }, (_, index) =>
    cellWidthBase + (index < cellWidthRemainder ? 1 : 0)
  );
  const rowHeights = Array.from({ length: rows }, (_, index) =>
    cellHeightBase + (index < cellHeightRemainder ? 1 : 0)
  );
  const xBoundaries = buildBoundaries(colWidths, marginPx);
  const yBoundaries = buildBoundaries(rowHeights, marginPx);
  const adjustedXBoundaries = applyOffsetToBoundaries(xBoundaries, offsetXPx);
  const adjustedYBoundaries = applyOffsetToBoundaries(yBoundaries, offsetYPx);

  const boxes: Box[] = [];
  for (let row = 0; row < rows; row += 1) {
    const yStart = adjustedYBoundaries[row] + row * gutterPx;
    const yEnd = adjustedYBoundaries[row + 1] + row * gutterPx;
    const rowHeight = yEnd - yStart;
    if (rowHeight <= 0) {
      return { boxes: [], warnings, error: offsetCollapseError("Y") };
    }
    for (let col = 0; col < cols; col += 1) {
      const xStart = adjustedXBoundaries[col] + col * gutterPx;
      const xEnd = adjustedXBoundaries[col + 1] + col * gutterPx;
      const colWidth = xEnd - xStart;
      if (colWidth <= 0) {
        return { boxes: [], warnings, error: offsetCollapseError("X") };
      }
      boxes.push({ x: xStart, y: yStart, width: colWidth, height: rowHeight });
    }
  }

  const outOfBounds = boxes.some(
    (box) =>
      box.x < 0 ||
      box.y < 0 ||
      box.x + box.width > width ||
      box.y + box.height > height
  );
  if (outOfBounds) {
    warnings.push("Some panels fall outside the image bounds.");
  }

  return { boxes, warnings };
}
