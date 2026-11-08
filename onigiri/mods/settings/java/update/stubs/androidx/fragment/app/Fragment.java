package androidx.fragment.app;
public abstract class Fragment {
    public final FragmentActivity getActivity() { throw null; }
    public android.content.Context getContext() { throw null; }
    public final boolean isAdded() { throw null; }
    public void onViewCreated(android.view.View v, android.os.Bundle b) { }
    public void onResume() { }
    public void onPause() { }
    public void startActivityForResult(android.content.Intent i, int request) { }
    public void onActivityResult(int request, int result, android.content.Intent data) { }
}
