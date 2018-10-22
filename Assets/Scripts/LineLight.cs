using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class LineLight : MonoBehaviour
{
    public float    length = 1;
    public float    range = 2;
    public float    luminance = 200;

    public Material lineMaterial;

    [Header("Debug")]
    public Vector3      targetPoint;
    public Quaternion   targetDirection = Quaternion.identity;

    public Vector3  p0 { get; private set; }
    public Vector3  p1 { get; private set; }

    public void Update()
    {
        lineMaterial.SetVector("_LightPosition", transform.position);
        lineMaterial.SetVector("_LightRight", transform.right);
        lineMaterial.SetVector("_LightUp", transform.up);
        lineMaterial.SetVector("_LightForward", transform.forward);
        lineMaterial.SetFloat("_Luminance", luminance);
        lineMaterial.SetFloat("_Range", range * transform.localScale.x);
        lineMaterial.SetFloat("_Length", length * transform.localScale.x);
        lineMaterial.SetMatrix("_LightModelMatrix", transform.localToWorldMatrix.inverse);
    }

    private void OnDrawGizmos()
    {
        float halfLength = length / 2;
        p0 = transform.TransformPoint(Vector3.left * halfLength);
        p1 = transform.TransformPoint(Vector3.right * halfLength);

        Gizmos.color = Color.green;
        Gizmos.DrawSphere(p0, 0.05f);
        Gizmos.DrawSphere(p1, 0.05f);
        Gizmos.DrawLine(p0, p1);
    }
}
