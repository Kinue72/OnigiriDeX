import java.lang.reflect.*;
import java.lang.invoke.*;
import java.util.concurrent.atomic.*;
/** Android-only: concurrent calls during hook installation must not recurse. Pass hma.jar path. */
public final class HmaHookRaceTest {
 static final AtomicInteger originals=new AtomicInteger(),calls=new AtomicInteger(),errors=new AtomicInteger();
 static final ThreadLocal<Integer> depth=ThreadLocal.withInitial(()->0);
 static volatile Method active;
 static volatile boolean done;
 public static void target0() { originals.incrementAndGet(); }
 public static void target1() { originals.incrementAndGet(); }
 public static void target2() { originals.incrementAndGet(); }
 public static void target3() { originals.incrementAndGet(); }
 public static void target4() { originals.incrementAndGet(); }
 public static void target5() { originals.incrementAndGet(); }
 public static void target6() { originals.incrementAndGet(); }
 public static void target7() { originals.incrementAndGet(); }
 public static void target8() { originals.incrementAndGet(); }
 public static void target9() { originals.incrementAndGet(); }
 public static void target10() { originals.incrementAndGet(); }
 public static void target11() { originals.incrementAndGet(); }
 public static void target12() { originals.incrementAndGet(); }
 public static void target13() { originals.incrementAndGet(); }
 public static void target14() { originals.incrementAndGet(); }
 public static void target15() { originals.incrementAndGet(); }
 public static void target16() { originals.incrementAndGet(); }
 public static void target17() { originals.incrementAndGet(); }
 public static void target18() { originals.incrementAndGet(); }
 public static void target19() { originals.incrementAndGet(); }
 public static void target20() { originals.incrementAndGet(); }
 public static void target21() { originals.incrementAndGet(); }
 public static void target22() { originals.incrementAndGet(); }
 public static void target23() { originals.incrementAndGet(); }
 public static void target24() { originals.incrementAndGet(); }
 public static void target25() { originals.incrementAndGet(); }
 public static void target26() { originals.incrementAndGet(); }
 public static void target27() { originals.incrementAndGet(); }
 public static void target28() { originals.incrementAndGet(); }
 public static void target29() { originals.incrementAndGet(); }
 public static void target30() { originals.incrementAndGet(); }
 public static void target31() { originals.incrementAndGet(); }
 public static void target32() { originals.incrementAndGet(); }
 public static void target33() { originals.incrementAndGet(); }
 public static void target34() { originals.incrementAndGet(); }
 public static void target35() { originals.incrementAndGet(); }
 public static void target36() { originals.incrementAndGet(); }
 public static void target37() { originals.incrementAndGet(); }
 public static void target38() { originals.incrementAndGet(); }
 public static void target39() { originals.incrementAndGet(); }
 public static void target40() { originals.incrementAndGet(); }
 public static void target41() { originals.incrementAndGet(); }
 public static void target42() { originals.incrementAndGet(); }
 public static void target43() { originals.incrementAndGet(); }
 public static void target44() { originals.incrementAndGet(); }
 public static void target45() { originals.incrementAndGet(); }
 public static void target46() { originals.incrementAndGet(); }
 public static void target47() { originals.incrementAndGet(); }

 public static void main(String[] args) throws Throwable {
  ClassLoader loader=(ClassLoader)Class.forName("dalvik.system.PathClassLoader").getConstructor(String.class, ClassLoader.class).newInstance(args[0], HmaHookRaceTest.class.getClassLoader());
  Class<?> hooks=Class.forName("com.v7878.vmtools.g",true,loader), transformer=Class.forName("com.v7878.vmtools.c",true,loader);
  Object callback=Proxy.newProxyInstance(loader,new Class[]{transformer},(p,m,a)-> {
    if (m.getName().equals("a")) {
     int d=depth.get(); if(d>32) throw new IllegalStateException("recursive original at depth="+d);
     depth.set(d+1); calls.incrementAndGet(); try { ((MethodHandle)a[0]).invokeWithArguments(); } finally { depth.set(d); } return null;
    }
    if (m.getName().equals("toString")) return "HmaHookRaceTest";
    return null;
  });
  Thread[] workers=new Thread[4];
  for(int i=0;i<workers.length;i++) {
   workers[i]=new Thread(()-> { while(!done) { Method m=active; if(m==null) continue; try { m.invoke(null); } catch(Throwable e) {if(errors.incrementAndGet()==1) e.printStackTrace();} } }); workers[i].start();
  }
  Method hook=hooks.getMethod("c",Executable.class,int.class,transformer);
  for(int i=0;i<48;i++) {
   active=HmaHookRaceTest.class.getMethod("target"+i);
   Thread.sleep(5); hook.invoke(null,active,1,callback); Thread.sleep(5);
  }
  done=true; for(Thread t:workers) t.join();
  System.out.println("originals="+originals+" hooks="+calls+" errors="+errors);
  System.exit(errors.get()==0?0:2);
 }
}
