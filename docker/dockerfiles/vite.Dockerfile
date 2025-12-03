FROM chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Normaliza finais de linha para evitar "no such file" em ambientes Windows
RUN sed -i 's/\r$//' docker/entrypoints/vite.sh && \
    chmod +x docker/entrypoints/vite.sh

EXPOSE 3036
CMD ["bin/vite", "dev"]
