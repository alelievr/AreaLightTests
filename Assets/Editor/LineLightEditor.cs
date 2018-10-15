using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using UnityEditor.IMGUI.Controls;

[CustomEditor(typeof(LineLight))]
public class LineLightEditor : Editor
{
    LineLight           line;
    SphereBoundsHandle  sphereHandle;

    private void OnEnable()
    {
        line = (LineLight)target;
        sphereHandle = new SphereBoundsHandle();
    }

    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();
    }

    float DistancePointLine(Vector3 a, Vector3 b, Vector3 p, out Vector3 nearestPoint)
    {
        Vector3 n = b - a;
        Vector3 pa = a - p;
        Vector3 c = n * (Vector3.Dot( pa, n ) / Vector3.Dot( n, n ));
        Vector3 d = pa - c;

        float n2 = Vector3.Dot(n, n);
        float abd = Vector3.Dot(pa, n);
        float t = abd / n2;

        nearestPoint = a - n * t;

        return Mathf.Sqrt( Vector3.Dot( d, d ) );
    }

    void DrawLineProjectionDebug()
    {
        Vector3 l1 = line.targetPoint - (line.targetPoint - line.p0) / 2;
        Vector3 l2 = line.targetPoint - (line.targetPoint - line.p1) / 2;
        Vector3 p0_t = Vector3.Normalize(line.p0 - line.targetPoint);
        Vector3 p1_t = Vector3.Normalize(line.p1 - line.targetPoint);
        Vector3 p0_p1 = Vector3.Normalize(line.p0 - line.p1);
        Vector3 p1_p0 = Vector3.Normalize(line.p1 - line.p0);
        float d = 0;
        Vector3 point;

        Handles.Label(l1, Vector3.Dot(p0_p1, p0_t).ToString());
        Handles.Label(l2, Vector3.Dot(p1_p0, p1_t).ToString());

        if (Vector3.Dot(p0_p1, p0_t) < 0)
        {
            d = Vector3.Magnitude(line.p0 - line.targetPoint);
            point = line.p0;
        }
        else if (Vector3.Dot(p1_p0, p1_t) < 0)
        {
            d = Vector3.Magnitude(line.p1 - line.targetPoint);
            point = line.p1;
        }
        else
            d = DistancePointLine(line.p0, line.p1, line.targetPoint, out point);

        Handles.color = Color.green;
        Handles.SphereHandleCap(0, point, Quaternion.identity, 0.5f, EventType.Repaint);

        Handles.color = Color.red;
        Handles.DrawDottedLine(point, line.targetPoint, 5f);

        Handles.Label(line.targetPoint, d.ToString());
    }

    float LineSDF(Vector3 p, Vector3 a, Vector3 b)
    {
        Vector3 pa = p - a, ba = b - a;
        float h = Mathf.Clamp01(Vector3.Dot(pa,ba) / Vector3.Dot(ba,ba));
        Vector3 t = (pa - ba * h);
        return Mathf.Sqrt(Vector3.Dot(t, t));
    }

    void DrawRaymarchDebug()
    {
        Vector3 normal = line.targetDirection * Vector3.forward;
        Vector3 p = line.targetPoint;
        float t = 0;
        float oldT = 1e20f;
        Vector3 lastPosition = line.targetPoint;

        float halfLength = line.range / 2;
        Vector3 p0 = line.transform.position - line.transform.right * halfLength;
        Vector3 p1 = line.transform.position + line.transform.right * halfLength;

        for (int i = 0; i < 4; i++)
        {
            t = LineSDF(p, p0, p1);
            p += normal * t;
            Handles.color += Color.red * 0.1f;
            Handles.SphereHandleCap(0, p, Quaternion.identity, .1f, EventType.Repaint);
            if (oldT < t)
                break;
            oldT = t;
            lastPosition = p;
        }

        Handles.color = Color.red;

        // TODO: compute the closest point in the direction of the sdf using p and lastPosition, t and oldT

        Handles.color = Color.yellow;
        Handles.DrawDottedLine(line.targetPoint, p, 5f);
    }

    void OnSceneGUI()
    {
        line.targetPoint = Handles.PositionHandle(line.targetPoint, Quaternion.identity);

        Handles.color = Color.blue;
        // Handles.DrawDottedLine(line.targetPoint, line.p0, 5f);
        // Handles.DrawDottedLine(line.targetPoint, line.p1, 5f);

        sphereHandle.center = line.transform.position;
        sphereHandle.radius = line.range;
        sphereHandle.DrawHandle();
        line.range = sphereHandle.radius;

        line.targetDirection = Handles.RotationHandle(line.targetDirection, line.targetPoint);

        Handles.ArrowHandleCap(0, line.targetPoint, line.targetDirection, 1f, EventType.Repaint);

        DrawRaymarchDebug();

        line.Update();
    }
}
