#!/usr/bin/python3
"""
Jetski Course Editor — FastAPI backend
Courses persist as JSON files in ./courses/

TrackSegment (mirrors C struct):
    curve  : int8  — total heading change in radian×32 over segment (−128=hard R … +127=hard L, 0=straight)
    length : uint16 — segment length in world units (cm)
    flags  : uint8  — HAS_RAMP=1, HAS_OBSTACLE_L=2, HAS_OBSTACLE_R=4,
                      SLOWZONE=8, SHORE_L=16, SHORE_R=32
"""
import json
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from typing import List
import uvicorn

COURSE_DIR = Path(__file__).parent / "courses"
COURSE_DIR.mkdir(exist_ok=True)
STATIC_DIR = Path(__file__).parent / "static"
STATIC_DIR.mkdir(exist_ok=True)

app = FastAPI(title="Jetski Course Editor")


class TrackSegment(BaseModel):
    curve: int = Field(0, ge=-128, le=127,
        description="Total heading change: radian×32 over segment length, signed")
    length: int = Field(500, ge=1, le=65535,
        description="Segment length in world units (cm)")
    flags: int = Field(0, ge=0, le=63,
        description="HAS_RAMP=1|HAS_OBSTACLE_L=2|HAS_OBSTACLE_R=4|SLOWZONE=8|SHORE_L=16|SHORE_R=32")


class Course(BaseModel):
    name: str
    difficulty: int = Field(1, ge=1, le=5)
    segments: List[TrackSegment] = []


def _safe_stem(name: str) -> str:
    """Return a filesystem-safe filename stem (alphanumeric, dash, underscore)."""
    return "".join(c for c in name if c.isalnum() or c in "-_").strip()


def _path(name: str) -> Path:
    stem = _safe_stem(name)
    if not stem:
        raise HTTPException(status_code=400, detail="Invalid course name")
    return COURSE_DIR / f"{stem}.json"


# ── Routes ────────────────────────────────────────────────────────────────

@app.get("/", include_in_schema=False)
def root():
    return FileResponse(STATIC_DIR / "editor.html")


@app.get("/courses/")
def list_courses() -> list:
    return sorted(p.stem for p in COURSE_DIR.glob("*.json"))


@app.get("/courses/{name}")
def get_course(name: str):
    p = _path(name)
    if not p.exists():
        raise HTTPException(status_code=404, detail="Course not found")
    return json.loads(p.read_text())


@app.post("/courses/", status_code=201)
def create_course(course: Course):
    p = _path(course.name)
    if p.exists():
        raise HTTPException(status_code=409, detail="Course already exists")
    p.write_text(course.model_dump_json(indent=2))
    return course


@app.put("/courses/{name}")
def save_course(name: str, course: Course):
    """Save (and optionally rename) a course. Old file removed on rename."""
    old_p = _path(name)
    new_p = _path(course.name)
    if old_p.exists() and old_p != new_p:
        old_p.unlink()
    new_p.write_text(course.model_dump_json(indent=2))
    return course


@app.delete("/courses/{name}", status_code=204)
def delete_course(name: str):
    p = _path(name)
    if not p.exists():
        raise HTTPException(status_code=404, detail="Course not found")
    p.unlink()


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

