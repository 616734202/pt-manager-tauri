// PT Manager headless 保活服务入口。
//
// 复用 src-tauri 的核心模块（通过 #[path] 指向同一份源码，不复制、不 fork），
// 只启动 Cron 调度 / 手动一轮保活，不创建任何窗口。桌面端代码完全不受影响。
#[path = "../../src-tauri/src/auth.rs"] mod auth;
#[path = "../../src-tauri/src/bark.rs"] mod bark;
#[path = "../../src-tauri/src/browser_proxy.rs"] mod browser_proxy;
#[path = "../../src-tauri/src/cdp.rs"] mod cdp;
#[path = "../../src-tauri/src/cookiecloud.rs"] mod cookiecloud;
#[path = "../../src-tauri/src/gotify.rs"] mod gotify;
#[path = "../../src-tauri/src/ocr.rs"] mod ocr;
#[path = "../../src-tauri/src/scheduler.rs"] mod scheduler;
#[path = "../../src-tauri/src/store.rs"] mod store;

use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

fn main() {
    // tauri::async_runtime 会懒创建并持有自己的 tokio runtime，
    // scheduler 内部的 spawn / spawn_blocking 全部依赖它，因此在这里统一驱动。
    tauri::async_runtime::block_on(async_main());
}

async fn async_main() {
    let once = std::env::args().any(|a| a == "--once");

    let config = store::load_config_headless();
    store::set_log_retention(config.log_retention);

    let logs = Arc::new(Mutex::new(store::load_logs()));
    browser_proxy::set_logs(Arc::clone(&logs));

    let task_running = Arc::new(Mutex::new(false));
    let task_cancel_requested = Arc::new(AtomicBool::new(false));

    eprintln!(
        "[headless] PT Manager 保活服务启动 | 数据目录: {} | 站点数: {}",
        store::headless_data_dir().display(),
        config.sites.len()
    );

    if once {
        eprintln!("[headless] 立即执行一轮保活（--once）");
        scheduler::run_with_flag(
            &config,
            &logs,
            &task_running,
            &task_cancel_requested,
            false,
            None,
            None,
        )
        .await;
        eprintln!("[headless] 本轮保活结束");
        return;
    }

    // Cron 定时保活
    let next_run = Arc::new(Mutex::new(None::<chrono::DateTime<chrono::Local>>));
    let mut scheduler = scheduler::Scheduler::new(Arc::clone(&next_run));
    scheduler.start(
        config.clone(),
        Arc::clone(&logs),
        Arc::clone(&task_running),
        Arc::clone(&task_cancel_requested),
        None,
        None,
    );

    eprintln!(
        "[headless] Cron: {} | 每轮随机延迟上限: {} 分钟",
        config.cron, config.cron_offset_minutes
    );
    eprintln!("[headless] 服务就绪，等待定时任务触发（Ctrl+C / SIGTERM 退出）");

    loop {
        tokio::time::sleep(Duration::from_secs(3600)).await;
    }
}
