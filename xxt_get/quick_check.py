"""
快速获取学习通未完成活动（随堂练习、签到、分组任务等）
精简版 - 只获取进行中的活动，不获取任务点
"""
import requests
import re
import time
from bs4 import BeautifulSoup as bs
from concurrent.futures import ThreadPoolExecutor, as_completed

# ========== 配置 ==========
MAX_WORKERS = 10      # 并发数（建议5-10）
REQUEST_TIMEOUT = 8  # 请求超时时间（秒）
# ==========================


def login(session, phone, pwd):
    """登录学习通"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }
    session.get('https://passport2.chaoxing.com/login')
    r = session.post('https://passport2.chaoxing.com/fanyalogin', headers=headers, data={
        'fid': '-1', 'uname': phone, 'password': pwd,
        'refer': 'https://i.chaoxing.com', 't': 'true'
    })
    result = r.json()
    if not result.get('status'):
        raise Exception(f"登录失败: {result.get('msg2', '未知错误')}")
    return headers


def get_courses(session, headers):
    """获取课程列表（直接从HTML属性提取，无需访问详情页）"""
    r = session.post('http://mooc1-1.chaoxing.com/visit/courselistdata', 
                     headers=headers, data={'courseType': 1, 'courseFolderId': 0, 'courseFolderSize': 0})
    soup = bs(r.text, 'html.parser')
    
    courses = []
    for li in soup.find_all('li', class_='course clearfix'):
        # 跳过已结课（检查多种标记方式）
        # 方式1: ui-open-review
        review = li.find(class_='ui-open-review')
        if review and '已开启结课模式' in review.text:
            continue
        # 方式2: not-open-tip (课程已结束)
        not_open = li.find(class_='not-open-tip')
        if not_open and '课程已结束' in not_open.text:
            continue
        
        courseid = li.get('courseid')
        clazzid = li.get('clazzid')
        if courseid and clazzid:
            courses.append({
                'name': li.find('span', class_='course-name').text.strip(),
                'courseid': courseid,
                'clazzid': clazzid
            })
    return courses


def get_activity_endtime(session, headers, active_id):
    """获取活动剩余时间"""
    try:
        url = f"https://mobilelearn.chaoxing.com/v2/apis/active/getActiveEndtime?DB_STRATEGY=PRIMARY_KEY&STRATEGY_PARA=activeId&activeId={active_id}"
        r = session.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
        data = r.json()
        if data.get('result') == 1 and data.get('data'):
            endtime = data['data'].get('endtime')
            if endtime:
                # 计算剩余时间
                remain = endtime - int(time.time() * 1000)
                if remain > 0:
                    remain_sec = remain // 1000
                    days = remain_sec // 86400
                    hours = (remain_sec % 86400) // 3600
                    minutes = (remain_sec % 3600) // 60
                    if days > 0:
                        return f"剩余 {days}天{hours}小时"
                    elif hours > 0:
                        return f"剩余 {hours}小时{minutes}分钟"
                    else:
                        return f"剩余 {minutes}分钟"
                else:
                    return "已超时"
            else:
                return "无截止时间"
    except:
        pass
    return ''


def check_activity_status(session, headers, active_id, active_type):
    """检查活动状态
    active_type: 2=签到, 35=分组任务, 42=随堂练习
    返回: '已签'/'未签'/'已交'/'未交'/'' (空字符串表示无法判断)
    """
    try:
        # 随堂练习使用 getAnswerResult API
        if active_type == '42':
            url = f"https://mobilelearn.chaoxing.com/v2/apis/studentQuestion/getAnswerResult?activeId={active_id}"
            r = session.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
            data = r.json()
            if data.get('result') == 1 and data.get('data'):
                if data['data'].get('isAnswered', False):
                    return '已交'
                return '未交'
        # 签到使用 signIn API 检查
        elif active_type == '2':
            url = f"https://mobilelearn.chaoxing.com/v2/apis/sign/signIn?activeId={active_id}"
            r = session.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
            data = r.json()
            # result=1 且 data 有值表示已签到
            if data.get('result') == 1 and data.get('data'):
                return '已签'
            return '未签'
        # 分组任务暂时无法检查
        elif active_type == '35':
            return ''
    except:
        pass
    return ''


def check_course(session, headers, course):
    """检查单个课程的进行中活动"""
    url = f"https://mobilelearn.chaoxing.com/widget/pcpick/stu/index?courseId={course['courseid']}&jclassId={course['clazzid']}"
    try:
        r = session.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
        soup = bs(r.text, 'html.parser')
        
        # 快速检查是否有进行中活动
        ongoing = soup.find('a', id='1')
        if not ongoing:
            return None
        
        match = re.search(r'\((\d+)\)', ongoing.get_text())
        count = int(match.group(1)) if match else 0
        
        if count == 0:
            return None
        
        # 提取活动详情
        activities = []
        start_list = soup.find('div', id='startList')
        if start_list:
            for mct in start_list.find_all('div', class_='Mct'):
                dd = mct.find('dd')
                center = mct.find('div', class_='Mct_center')
                a = center.find('a') if center else None
                
                # 从 Mct div 的 onclick 提取 activeId 和 activeType
                active_id = None
                active_type = None
                onclick = mct.get('onclick', '')
                # 解析 onclick="activeDetail(5000140963764,35,null)"
                match_id = re.search(r'activeDetail\((\d+),(\d+)', onclick)
                if match_id:
                    active_id = match_id.group(1)
                    active_type = match_id.group(2)
                
                # 检查活动状态（随堂练习和签到）
                status = ''
                if active_id and active_type in ('42', '2'):
                    status = check_activity_status(session, headers, active_id, active_type)
                
                # 获取剩余时间
                time_info = ''
                if active_id:
                    time_info = get_activity_endtime(session, headers, active_id)
                
                activities.append({
                    'type': dd.get_text(strip=True) if dd else '未知',
                    'name': a.get_text(strip=True) if a else '未知',
                    'time': time_info,
                    'status': status
                })
        
        if not activities:
            return None
        
        return {'course': course['name'], 'activities': activities}
    except:
        return None


def main():
    print("=" * 50)
    print("  学习通未完成活动快速检查")
    print("=" * 50)
    
    phone = input('\n手机号: ')
    pwd = input('密码: ')
    
    session = requests.session()
    
    print("\n⏳ 登录中...")
    try:
        headers = login(session, phone, pwd)
        print("✅ 登录成功")
    except Exception as e:
        print(f"❌ {e}")
        return
    
    print("⏳ 获取课程列表...")
    courses = get_courses(session, headers)
    print(f"📚 共 {len(courses)} 门课程")
    
    print(f"⏳ 检查进行中活动 (并发数: {MAX_WORKERS})...")
    start = time.time()
    
    results = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(check_course, session, headers, c) for c in courses]
        for f in as_completed(futures):
            r = f.result()
            if r:
                results.append(r)
    
    elapsed = time.time() - start
    print(f"✅ 完成，耗时 {elapsed:.1f} 秒")
    
    # 输出结果
    print("\n" + "=" * 50)
    if results:
        print(f"📋 发现 {len(results)} 门课程有进行中活动：")
        print("-" * 50)
        for r in results:
            print(f"\n📚 {r['course']}")
            for act in r['activities']:
                # 状态标记
                status = act.get('status', '')
                if status == '已签':
                    status_str = ' ✅已签'
                elif status == '未签':
                    status_str = ' ❌未签'
                elif status == '已交':
                    status_str = ' ✅已交'
                elif status == '未交':
                    status_str = ' ❌未交'
                else:
                    status_str = ''
                
                time_str = f" ⏰ {act['time']}" if act.get('time') else ''
                print(f"   ⚡ [{act['type']}] {act['name'][:40]}{status_str}{time_str}")
    else:
        print("✅ 太棒了！没有进行中的活动！")
    print("=" * 50)


if __name__ == '__main__':
    main()
