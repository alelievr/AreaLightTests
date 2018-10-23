using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class LineLight : MonoBehaviour
{
    public float        length = 1;
    public float        width = 0;
    public float        range = 2;
    public float        luminance = 200;
    public LightMode    mode;
    public bool         affectSpecular;
    public bool         affectDiffuse;

    public Material     lineMaterial;

    [Header("Debug")]
    public Vector3      targetPoint;
    public Quaternion   targetDirection = Quaternion.identity;

    public Vector3  p0 { get; private set; }
    public Vector3  p1 { get; private set; }

    public enum LightMode
    {
        Cross,
        Torus,
        Quad,
        Line,
    }

    public void Update()
    {
        lineMaterial.SetVector("_LightPosition", transform.position);
        lineMaterial.SetVector("_LightRight", transform.right);
        lineMaterial.SetVector("_LightUp", transform.up);
        lineMaterial.SetVector("_LightForward", transform.forward);
        lineMaterial.SetFloat("_Luminance", luminance);
        lineMaterial.SetFloat("_Range", range * transform.localScale.x);
        lineMaterial.SetFloat("_Length", length * transform.localScale.x);
        lineMaterial.SetFloat("_Width", width * transform.localScale.y);
        lineMaterial.SetMatrix("_LightModelMatrix", transform.localToWorldMatrix.inverse);
        lineMaterial.SetInt("_LightMode", (int)mode);
        lineMaterial.SetInt("_AffectDiffuse", affectDiffuse ? 1 : 0);
        lineMaterial.SetInt("_AffectSpecular", affectSpecular ? 1 : 0);
    }

    private void OnDrawGizmos()
    {
        switch (mode)
        {
            case LightMode.Torus:
                DrawTorusGizmo();
                break;
            case LightMode.Cross:
                DrawCrossGizmo();
                break;
            case LightMode.Quad:
                DrawQuadGizmo();
                break;
            default:
                DrawLineGizmo();
                break;
        }
    }

    void DrawLineGizmo()
    {
        float halfLength = length / 2;
        p0 = transform.TransformPoint(Vector3.left * halfLength);
        p1 = transform.TransformPoint(Vector3.right * halfLength);

        Gizmos.color = Color.green;
        Gizmos.DrawSphere(p0, 0.05f);
        Gizmos.DrawSphere(p1, 0.05f);
        Gizmos.DrawLine(p0, p1);
    }

    void DrawCrossGizmo()
    {

    }

    void DrawQuadGizmo()
    {
        float halfLength = length / 2;
        float halfWidth = width / 2;
        p0 = transform.TransformPoint(Vector3.left * halfLength);
        p1 = transform.TransformPoint(Vector3.right * halfLength);
        // p2 = transform.TransformPoint(Vector3.forward * halfLength);
        // p3 = transform.TransformPoint(Vector3.back * halfLength);

        Gizmos.color = new Color(0, 1, 0, .2f);
        Matrix4x4 oldMatrix = Gizmos.matrix;
        Gizmos.matrix = transform.localToWorldMatrix;
        Gizmos.DrawCube(Vector3.zero, new Vector3(length, 0, width));
        Gizmos.matrix = oldMatrix;

    }

    void DrawTorusGizmo()
    {
        Gizmos.color = Color.green;
        Matrix4x4 oldMatrix = Gizmos.matrix;
        Gizmos.matrix = transform.localToWorldMatrix * Matrix4x4.Rotate(Quaternion.Euler(new Vector3(90, 0, 0)));
        int segments = 50;
        Vector2 p0 = new Vector2(Mathf.Sin(0), Mathf.Cos(0)) * range;
        for (int i = 0; i <= segments; i++)
        {
            float a = ((float)i / (float)segments) * Mathf.PI * 2;
            Vector2 p1 = new Vector2(Mathf.Sin(a), Mathf.Cos(a)) * range;
            Gizmos.DrawLine(p0, p1);
            p0 = p1;
        }
        Gizmos.matrix = oldMatrix;
    }
}
