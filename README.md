Git 全局设置:
git config --global user.name "Guo214"
git config --global user.email "12654558+guo214@user.noreply.gitee.com"

创建 git 仓库:
mkdir install-k8s
cd install-k8s
git init 
touch README.md
git add README.md
git commit -m "first commit"
git remote add origin https://github.com/guo214/install-k8s.git
git push -u origin "main"

已有仓库：
cd existing_git_repo
git remote add origin https://github.com/guo214/install-k8s.git
git push -u origin "main"
