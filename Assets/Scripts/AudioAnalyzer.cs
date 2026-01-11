using UnityEngine;

[RequireComponent(typeof(AudioSource))]
public class AudioAnalyzer : MonoBehaviour
{
    [Tooltip("Assign an AudioSource or the component will try to find one on this GameObject")]
    public AudioSource audioSource;

    [Tooltip("Number of samples used for spectrum analysis. Will be clamped to a power-of-two.")]
    public int sampleRate = 1024; // power-of-two values recommended: 256, 512, 1024, 2048

    [HideInInspector]
    public float[] samples;

    [Range(0f, 100f)]
    public float sensitivity = 20f; // scales RMS to a usable 0..1 range

    [Tooltip("If set, the analyzer will write the audio level to the global shader float '_AudioLevel'.")]
    public bool setGlobalShaderFloat = true;

    // Output values
    public float audioLevel; // RMS-scaled value in 0..1 (after sensitivity) — if autoNormalize=true, this is the normalized value
    public float normalizedAudioLevel; // normalized level (0..1) after adaptive normalization
    public float peakLevel; // maximum spectral bin value seen this frame

    [Header("Normalization")]
    [Tooltip("Automatically normalize audio levels to be stable across different volumes")]
    public bool autoNormalize = true;
    [Tooltip("Exponential decay time (seconds) for the running peak used for normalization")]
    public float normalizationDecay = 1.0f;
    [Tooltip("Smoothing time (seconds) applied to RMS before normalization")]
    public float smoothingTime = 0.03f;
    [Tooltip("Extra gain applied after normalization to scale the output")]
    public float normalizationGain = 1.0f;

    // Internal smoothing state
    private float smoothedRms = 0f;
    private float runningMaxRms = 1e-6f;

    void Start()
    {
        // Try to auto-assign the AudioSource if the user didn't set it in the inspector
        if (audioSource == null)
            audioSource = GetComponent<AudioSource>();

        if (audioSource == null)
        {
            Debug.LogWarning("AudioAnalyzer: No AudioSource assigned or found on the GameObject. Disabling AudioAnalyzer.");
            enabled = false;
            return;
        }

        if (sampleRate <= 0)
            sampleRate = 1024;

        // Ensure the sample size is a power of two for spectrum analysis
        sampleRate = Mathf.ClosestPowerOfTwo(sampleRate);
        samples = new float[sampleRate];

        // Initialize smoothing state for normalization
        smoothedRms = 0f;
        runningMaxRms = 1e-6f;
    }

    void Update()
    {
        // Fill the spectrum array; channel 0, using BlackmanHarris window
        audioSource.GetSpectrumData(samples, 0, FFTWindow.BlackmanHarris);

        // Compute RMS (more stable than a simple mean) and the peak bin value
        float sumSquares = 0f;
        float max = 0f;
        for (int i = 0; i < samples.Length; i++)
        {
            float s = samples[i];
            sumSquares += s * s;
            if (s > max) max = s;
        }

        float rms = Mathf.Sqrt(sumSquares / samples.Length);
        peakLevel = max;

        if (autoNormalize)
        {
            // Smooth the RMS with an exponential filter (time constant = smoothingTime)
            float smoothAlpha = 1.0f - Mathf.Exp(-Time.deltaTime / Mathf.Max(0.0001f, smoothingTime));
            smoothedRms = Mathf.Lerp(smoothedRms, rms, smoothAlpha);

            // Update running max with exponential decay so recent peaks set the normalization reference
            float decayFactor = Mathf.Exp(-Time.deltaTime / Mathf.Max(0.0001f, normalizationDecay));
            runningMaxRms = Mathf.Max(smoothedRms, runningMaxRms * decayFactor);

            // Normalized level (0..1), scaled by normalizationGain
            normalizedAudioLevel = Mathf.Clamp01((smoothedRms / (runningMaxRms + 1e-6f)) * normalizationGain);
            audioLevel = normalizedAudioLevel; // legacy field now holds the normalized value when autoNormalize is enabled
        }
        else
        {
            audioLevel = Mathf.Clamp01(rms * sensitivity);
            normalizedAudioLevel = audioLevel;
        }

        // Optionally expose the value to shaders as a global float _AudioLevel (normalized if autoNormalize)
        if (setGlobalShaderFloat)
            Shader.SetGlobalFloat("_AudioLevel", audioLevel);
    }
}
