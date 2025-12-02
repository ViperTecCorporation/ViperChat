class SuperAdmin::SettingsController < SuperAdmin::ApplicationController
  def show; end

  def refresh
    # Desabilitado: apenas retorna objeto vazio sem disparar job
    render json: {}
  end
end
