require 'test_helper'

class CompaniesControllerTest < ActionController::TestCase
  setup do
    @company = companies(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:companies)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create company" do
    assert_difference('Company.count') do
      post :create, company: { angellist_url: @company.angellist_url, category: @company.category, crunchbase_url: @company.crunchbase_url, description: @company.description, employee_count: @company.employee_count, founded_date: @company.founded_date, location: @company.location, main_url: @company.main_url, name: @company.name, twitter_url: @company.twitter_url }
    end

    assert_redirected_to company_path(assigns(:company))
  end

  test "should show company" do
    get :show, id: @company
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @company
    assert_response :success
  end

  test "should update company" do
    patch :update, id: @company, company: { angellist_url: @company.angellist_url, category: @company.category, crunchbase_url: @company.crunchbase_url, description: @company.description, employee_count: @company.employee_count, founded_date: @company.founded_date, location: @company.location, main_url: @company.main_url, name: @company.name, twitter_url: @company.twitter_url }
    assert_redirected_to company_path(assigns(:company))
  end

  test "should destroy company" do
    assert_difference('Company.count', -1) do
      delete :destroy, id: @company
    end

    assert_redirected_to companies_path
  end
end
