# Plain static site on Nginx. Single stage: there is nothing to compile.
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
# The nginx base image already sets `nginx -g "daemon off;"` as its CMD,
# so there is no need to repeat it here.
