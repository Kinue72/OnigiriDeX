package com.android.server.wm;

import android.content.Context;
import java.util.HashMap;

public class WindowManagerService {
    public ActivityTaskManagerService mAtmService;
    public Context mContext;
    public WindowManagerGlobalLock mGlobalLock;
    public HashMap mInputToWindowMap;
    public RootWindowContainer mRoot;
}
