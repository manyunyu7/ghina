"use client";

import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, Legend,
} from "recharts";

type WeightPoint = { label: string; weight: number };
type BpPoint = { label: string; systolic: number; diastolic: number };

const axis = { fontSize: 12, fill: "#94a3b8" };

export function WeightChart({ data }: { data: WeightPoint[] }) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#eef0f6" vertical={false} />
        <XAxis dataKey="label" tick={axis} tickLine={false} axisLine={false} />
        <YAxis tick={axis} tickLine={false} axisLine={false} width={40} domain={["dataMin - 1", "dataMax + 1"]} />
        <Tooltip
          contentStyle={{ borderRadius: 12, border: "1px solid #e6e8f0", fontSize: 13 }}
          formatter={(v) => [`${v} kg`, "Weight"]}
        />
        <Line type="monotone" dataKey="weight" stroke="#6366f1" strokeWidth={2.5} dot={{ r: 3 }} activeDot={{ r: 5 }} />
      </LineChart>
    </ResponsiveContainer>
  );
}

export function BloodPressureChart({ data }: { data: BpPoint[] }) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#eef0f6" vertical={false} />
        <XAxis dataKey="label" tick={axis} tickLine={false} axisLine={false} />
        <YAxis tick={axis} tickLine={false} axisLine={false} width={40} domain={[40, "dataMax + 10"]} />
        <Tooltip contentStyle={{ borderRadius: 12, border: "1px solid #e6e8f0", fontSize: 13 }} />
        <Legend iconType="plainline" wrapperStyle={{ fontSize: 12 }} />
        <Line type="monotone" dataKey="systolic" name="Systolic" stroke="#ef4444" strokeWidth={2.5} dot={{ r: 3 }} />
        <Line type="monotone" dataKey="diastolic" name="Diastolic" stroke="#3b82f6" strokeWidth={2.5} dot={{ r: 3 }} />
      </LineChart>
    </ResponsiveContainer>
  );
}
