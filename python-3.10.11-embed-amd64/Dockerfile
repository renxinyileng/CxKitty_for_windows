FROM python:3.13

ENV TZ="Asia/Shanghai"

# 安装必要组件
# linux 下依赖 opencv-python-headless, 无需再安装 libgl 等 GUI 系统库
RUN pip install --no-cache-dir "poetry>=2.0,<3"

# 安装依赖
WORKDIR /app
COPY ["pyproject.toml", "poetry.lock", "README.md", "/app/"]
RUN poetry config virtualenvs.in-project true && \
    poetry install --only main

# 添加源文件
COPY . /app

ENTRYPOINT ["poetry", "run", "python3", "main.py"]
