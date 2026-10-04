/// Built-in texts. Every non-comment line must evaluate (see GuideTests).
public enum Guide {
    /// Title of the built-in syntax reference (Help menu). It is never saved as a file.
    public static let title = "语法速查"

    /// The short sample shown in the untitled note on first launch.
    public static let welcome = """
    # 欢迎使用 Numo，输入算式，右侧实时出结果

    1 + 1
    100$ to ¥
    √π
    20% of 150
    sin 30°

    价格 = 299 × 0.85
    价格 × 3
    prev − 10%

    房租 3000¥
    餐饮 200$
    合计
    """

    public static let text = """
    # 语法速查
    # 每行一个算式，右侧实时显示结果
    # # 开头的行和 // 之后的内容是注释

    # ── 基础运算 ──
    1 + 2 × 3  // 加减乘除，输入的 * 会显示为 ×
    (1 + 2) × 3  // 括号改变优先级
    2 ^ 10  // 幂，也可以写 2 ** 10
    17 mod 5  // 取余
    5!  // 阶乘
    2(3 + 4)  // 数字紧跟括号表示相乘
    1,000,000 ÷ 4  // 千分位逗号会被忽略
    1.5e3  // 科学计数法输入
    0.1 + 0.2  // 十进制精确计算，没有浮点误差

    # ── 根号、常量与函数 ──
    √16  // 平方根，也可以写 sqrt(16)
    ∛27  // 立方根
    2π  // 常量 π、e 可直接使用
    sin 30°  // ° 表示角度，不加则按弧度
    cos(π / 3)  // 函数参数可以加括号
    log 1000  // 以 10 为底的对数
    ln e  // 自然对数
    log2 1024  // 以 2 为底的对数
    abs(−8)  // 绝对值
    round 3.6  // 四舍五入，另有 floor / ceil

    # ── 百分比 ──
    20% of 150  // 求某数的百分之几
    200 + 10%  // 在原数上增加 10%
    200 − 25%  // 在原数上减少 25%
    50 / 200 to %  // 换算成百分比

    # ── 货币换算 ──
    100$ to ¥  // to、in、=、→ 都表示换算
    100 usd in eur  // 也可以用货币代码
    1$ = ¥  // 写成等式同样可以
    100美元换成人民币  // 支持中文货币名
    50€ + 20$  // 不同货币相加，以第一个货币为准
    1000 jpy to ¥  // ¥ 默认是人民币，日元写 jpy 或 日元

    # ── 变量与引用 ──
    单价 = 299 × 0.85  // 定义变量
    单价 × 3  // 使用变量
    prev − 10%  // prev 表示上一行的结果

    # ── 进制与格式 ──
    0xFF + 0b1010  // 十六进制、二进制输入
    255 in hex  // 转为十六进制，另有 bin / oct
    1234567 to sci  // 转为科学计数法

    # ── 标签与合计 ──
    # 行首的文字会作为标签；空行把内容分成不同的块
    房租 3000¥
    水电 260¥
    餐饮 200$
    合计  // 对当前块求和，也可以写 sum / total

    # ── 小技巧 ──
    # 点击结果拷贝数值，⇧⌘C 拷贝光标所在行的结果
    # ⌥Space 随时呼出或隐藏 Numo，⌘, 打开设置
    """
}
