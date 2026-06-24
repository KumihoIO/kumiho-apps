import { describe, expect, it } from "vitest";
import { computeBoxes } from "./slicing";

describe("computeBoxes", () => {
  it("returns grid boxes for valid input", () => {
    const result = computeBoxes({
      width: 400,
      height: 400,
      rows: 2,
      cols: 2,
      margin: 0,
      gutter: 0,
      offsetX: 0,
      offsetY: 0
    });

    expect(result.error).toBeUndefined();
    expect(result.boxes).toHaveLength(4);
    expect(result.boxes[0]).toMatchObject({ x: 0, y: 0, width: 200, height: 200 });
  });

  it("flags invalid grid sizes", () => {
    const result = computeBoxes({
      width: 100,
      height: 100,
      rows: 0,
      cols: 3,
      margin: 0,
      gutter: 0,
      offsetX: 0,
      offsetY: 0
    });

    expect(result.error).toContain("Rows and columns");
  });

  it("errors when margins exceed bounds", () => {
    const result = computeBoxes({
      width: 100,
      height: 100,
      rows: 2,
      cols: 2,
      margin: 60,
      gutter: 0,
      offsetX: 0,
      offsetY: 0
    });

    expect(result.error).toContain("Grid exceeds");
  });

  it("moves interior lines without shifting the contact sheet edges", () => {
    const result = computeBoxes({
      width: 200,
      height: 200,
      rows: 1,
      cols: 2,
      margin: 0,
      gutter: 0,
      offsetX: 10,
      offsetY: 0
    });

    expect(result.error).toBeUndefined();
    expect(result.boxes).toHaveLength(2);
    expect(result.boxes[0]).toMatchObject({ x: 0, width: 110 });
    expect(result.boxes[1]).toMatchObject({ x: 110, width: 90 });
    expect(result.boxes[1].x + result.boxes[1].width).toBe(200);
  });

  it("errors when offsets collapse the grid", () => {
    const result = computeBoxes({
      width: 200,
      height: 200,
      rows: 2,
      cols: 2,
      margin: 0,
      gutter: 0,
      offsetX: 200,
      offsetY: 0
    });

    expect(result.error).toContain("Offset");
    expect(result.boxes).toHaveLength(0);
  });

  it("respects gutter spacing between panels", () => {
    const result = computeBoxes({
      width: 210,
      height: 100,
      rows: 1,
      cols: 2,
      margin: 0,
      gutter: 10,
      offsetX: 0,
      offsetY: 0
    });

    expect(result.error).toBeUndefined();
    expect(result.boxes[0].x + result.boxes[0].width + 10).toBe(result.boxes[1].x);
  });
});
