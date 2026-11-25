package android.app;

/** Shadows the SDK class for the hidden getWindowingMode(). */
public class TaskInfo {
    public int taskId;
    public int getWindowingMode() { return 0; }
}
